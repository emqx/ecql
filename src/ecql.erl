%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015 eMQTT.IO, All Rights Reserved.
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------
%%% @doc CQL Driver.
%%%
%%% @author Feng Lee <feng@emqtt.io>
%%%-----------------------------------------------------------------------------

-module(ecql).

-behaviour(gen_fsm).

-include("ecql.hrl").

-include("ecql_types.hrl").

-import(proplists, [get_value/2, get_value/3]).

%% API Function Exports
-export([start_link/1, start_link/2, options/1, query/2, query/3,
         prepare/2, execute/3, execute/4]).

%% gen_fsm Function Exports
-export([startup/2, startup/3, waiting_for_ready/2, waiting_for_ready/3,
         waiting_for_auth/2, waiting_for_auth/3, established/2, established/3,
         disconnected/2, disconnected/3]).

-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

-type host() :: inet:ip_address() | inet:hostname().

-type option() :: {nodes,    [{host(), inet:port_number()}]}
                | {username, binary()}
                | {password, binary()}
                | {ssl,      boolean()}
                | {ssl_opts, [ssl:ssl_option()]}
                | {timeout,  timeout()}
                | {logger,   atom() | {atom(), atom()}}.

-record(state, {nodes     :: [{host(), inet:port_number()}],
                username  :: binary(),
                password  :: binary(),
                transport :: tcp | ssl,
                socket    :: inet:socket(),
                receiver  :: pid(),
                callers   :: list(),
                requests  :: dict:dict(),
                prepared  :: list(),
                logger    :: gen_logger:logmod(),
                ssl       :: boolean(),
                ssl_opts  :: [ssl:ssl_option()], 
                tcp_opts  :: [gen_tcp:connect_option()],
                compression :: boolean(),
                proto_state}).

-define(LOG(Logger, Level, Format, Args),
        Logger:Level("[ecql~p] " ++ Format, [self() | Args])).

-define(PASSWORD_AUTHENTICATOR, <<"org.apache.cassandra.auth.PasswordAuthenticator">>).

-type cql_result() :: {TableSpec :: binary(),
                       Columns   :: [tuple()],
                       Rows      :: list()}.

%% API Function Definitions

-spec start_link([option()]) -> {ok, pid()} | {error, any()}.
start_link(Opts) ->
    start_link(Opts, []).

-spec start_link([option()], [gen_tcp:connect_option()])
        -> {ok, pid()} | {error, any()}.
start_link(Opts, TcpOpts) ->
    case gen_fsm:start_link(?MODULE, [Opts], []) of
        {ok, Pid} ->
            connect(Pid, TcpOpts);
        {error, Error} ->
            {error, Error}
    end.

connect(Pid, TcpOpts) ->
    case gen_fsm:sync_send_event(Pid, {connect, TcpOpts}) of
        ok             -> {ok, Pid};
        {error, Error} -> {error, Error}
    end.

-spec options(pid()) -> {ok, list()} | {error, any()}.
options(Pid) ->
    gen_fsm:sync_send_all_state_event(Pid, options).

-spec query(pid(), binary()) -> {ok, cql_result()} | {error, any()}.
query(Pid, Query) when is_binary(Query) ->
    query(Pid, Query, ?CL_ONE).

query(Pid, Query, CL) when is_binary(Query) andalso is_atom(CL) ->
    query(Pid, Query, ecql_cl:value(CL));

query(Pid, Query, CL) when is_binary(Query) andalso ?IS_CL(CL) ->
    query(Pid, Query, CL, undefined).

query(Pid, Query, CL, Values) when is_binary(Query) andalso ?IS_CL(CL) ->
    gen_fsm:sync_send_event(Pid, {query, #ecql_query{query = Query, consistency  = CL, values = Values}}).

prepare(Pid, Query) when is_list(Query) -> 
    prepare(Pid, list_to_binary(Query));

prepare(Pid, Query) when is_binary(Query) -> 
    gen_fsm:sync_send_event(Pid, {prepare, Query}).

execute(C, Id, CL) when is_binary(Id) andalso ?IS_CL(CL) ->
    execute(C, Id, #ecql_query{consistency = ecql_cl:value(CL)});

execute(C, Id, Query) when is_binary(Id), is_record(Query, ecql_query) ->
    gen_fsm:sync_send_event(C, {execute, Id, Query}).

execute(C, Id, CL, Values) when is_binary(Id) andalso ?IS_CL(CL) ->
    execute(C, Id, #ecql_query{consistency = ecql_cl:value(CL),
                               values = Values}).

%% gen_fsm Function Definitions

init([Opts]) ->
    process_flag(trap_exit, true),
    random:seed(os:timestamp()),
    Nodes = get_value(nodes, Opts, [{"127.0.0.1", 9042}]),
    Username = bin(get_value(username, Opts)),
    Password = bin(get_value(password, Opts)),
    IsSSL = get_value(ssl, Opts, false),
    SslOpts = get_value(ssl_opts, Opts, []),
    Transport = if IsSSL -> ssl; true -> tcp end,
    Logger = gen_logger:new(get_value(logger, Opts, {console, debug})),
    {ok, startup, #state{nodes     = Nodes,
                         username  = Username,
                         password  = Password,
                         callers   = [],
                         requests  = dict:new(),
                         ssl       = IsSSL,
                         ssl_opts  = SslOpts,
                         transport = Transport,
                         logger    = Logger}}.

startup(Event, StateData = #state{logger = Logger}) ->
    Logger:error("[startup]: Unexpected Event: ~p", [Event]),
    {next_state, startup, StateData}.

startup({connect, TcpOpts}, From, State = #state{callers = Callers}) ->
    case connect_cassa(State#state{tcp_opts = TcpOpts}) of
        {ok, NewState = #state{proto_state = ProtoState}} ->
            {_, NewProto} = ecql_proto:startup(ProtoState),
            {next_state, waiting_for_ready, NewState#state{
                    callers = [{connect, From}|Callers], proto_state = NewProto}};
        Error ->
            {stop, Error, Error, State}
    end.

waiting_for_ready(?READY_FRAME, State = #state{callers = Callers}) ->
    {next_state, established, State#state{callers = reply(connect, ok, Callers)}};

waiting_for_ready(?RESP_FRAME(?OP_ERROR, #ecql_error{message = Message}), State = #state{callers = Callers}) ->
    shutdown(ecql_error, State#state{callers = reply(connect, {error, Message}, Callers)});

waiting_for_ready(?RESP_FRAME(StreamId, ?OP_AUTHENTICATE, #ecql_authenticate{class = ?PASSWORD_AUTHENTICATOR}),
                  State = #state{username = Username, password = Password, proto_state = ProtoState}) ->
    Token = auth_token(Username, Password),
    {_Frame, NewProtoState} = ecql_proto:auth_response(StreamId, Token, ProtoState),
    {next_state, waiting_for_auth, State#state{proto_state = NewProtoState}};

waiting_for_ready(?RESP_FRAME(?OP_AUTHENTICATE, #ecql_authenticate{class = Class}),
                  State = #state{callers = Callers}) ->
    reply(connect, {error, {unsupported_auth_class, Class}}, Callers),
    shutdown({auth_error, Class}, State);

waiting_for_ready(_Event, State) ->
    %%TODO:...
    {next_state, waiting_for_ready, State}.

waiting_for_ready(_Event, _From, State) ->
    {reply, {error, waiting_for_ready}, waiting_for_ready, State}.

waiting_for_auth(?RESP_FRAME(?OP_AUTH_CHALLENGE, #ecql_auth_challenge{token = Token}),
                 State = #state{callers = Callers, logger = Logger}) ->
    ?LOG(Logger, error, "Auth Challenge: ~p", [Token]),
    shutdown(password_error, State#state{callers = reply(connect, {error, password_error}, Callers)});

waiting_for_auth(?RESP_FRAME(?OP_AUTH_SUCCESS, #ecql_auth_success{token = Token}),
                 State = #state{callers = Callers, logger = Logger}) ->
    ?LOG(Logger, info, "Auth Success: ~p", [Token]),
    {next_state, established, State#state{callers = reply(connect, ok, Callers)}};

waiting_for_auth(?RESP_FRAME(?OP_ERROR, #ecql_error{message = Message}),
                 State = #state{callers = Callers}) ->
    io:format("Auth Error: ~p~n", [Message]),
    Callers1 = reply(connect, {error, {auth_failed, Message}}, Callers),
    shutdown(auth_error, State#state{callers = Callers1});

waiting_for_auth(_Event, State) ->
    %TODO:...
    {next_state, waiting_for_auth, State}.

waiting_for_auth(_Event, _From, StateData) ->
    {reply, {error, waiting_for_auth}, waiting_for_auth, StateData}.

established(Frame, State = #state{logger = Logger})
        when is_record(Frame, ecql_frame) ->
    ?LOG(Logger, info, "Frame ~p", [Frame]),
    NewState = received(Frame, State),
    {next_state, established, NewState, hibernate};

established(_Event, State) ->
    {next_state, established, State}.

established({query, Query}, From, State = #state{proto_state = ProtoSate})
        when is_record(Query, ecql_query) ->
    request(From, fun ecql_proto:query/2, [Query, ProtoSate], State);

established({prepare, Query}, From, State = #state{proto_state = ProtoSate}) ->
    request(From, fun ecql_proto:prepare/2, [Query, ProtoSate], State);

established({execute, Id, Query}, From, State = #state{proto_state = ProtoSate}) ->
    request(From, fun ecql_proto:execute/3, [Id, Query, ProtoSate], State);

established(_Event, _From, State) ->
    {reply, {error, unsupported}, established, State}.

request(From, Fun, Args, State = #state{requests = Reqs}) ->
    {Frame, ProtoState} = apply(Fun, Args),
    {next_state, established, State#state{proto_state = ProtoState,
            requests = dict:store(ecql_frame:stream(Frame), From, Reqs)}}.

disconnected(_Event, State) ->
    {next_state, state_name, State}.

disconnected(_Event, _From, State) ->
    {reply, ok, state_name, State}.

handle_event({frame_error, Error}, _StateName, State = #state{logger = Logger}) ->
    ?LOG(Logger, error, "Frame Error: ~p", [Error]),
    shutdown({frame_error, Error}, State);

handle_event({connection_lost, Reason}, _StateName, State= #state{logger = Logger}) ->
    ?LOG(Logger, warning, "Connection lost for: ~p", [Reason]),
     shutdown(Reason, State#state{socket = undefined, receiver = undefined});

handle_event(Event, StateName, State = #state{logger = Logger}) ->
    ?LOG(Logger, warning, "Unexpected Event when ~s: ~p", [StateName, Event]),
    {next_state, StateName, State}.

handle_sync_event(options, From, StateName, State = #state{requests = Reqs,
                                                           proto_state = ProtoState})
        when StateName =:= established;
             StateName =:= waiting_for_ready;
             StateName =:= waiting_for_auth ->
    {Frame, ProtoState1} = ecql_proto:options(ProtoState),
    Reqs1 = dict:store(ecql_frame:stream(Frame), From, Reqs),
    {next_state, StateName, State#state{proto_state = ProtoState1,
                                        requests    = Reqs1}};

handle_sync_event(options, _From, StateName, State) ->
    {reply, {error, StateName}, StateName, State};

handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ok, StateName, State}.

handle_info(Frame, established, State) ->
    io:format("~p~n", [Frame]),
    {next_state, established, State};

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% Internal Function Definitions
connect_cassa(State = #state{nodes     = Nodes,
                             transport = Transport,
                             tcp_opts  = TcpOpts,
                             logger    = Logger}) ->
    {Host, Port} = lists:nth(crypto:rand_uniform(1, length(Nodes) + 1), Nodes),
    ?LOG(Logger, info, "connecting to ~s:~p", [Host, Port]),
    case ecql_sock:connect(self(), Transport, Host, Port, TcpOpts, Logger) of
        {ok, Sock, Receiver} ->
            ?LOG(Logger, info, "connected with ~s:~p", [Host, Port]),
            SendFun = fun(Frame) ->
                    Data = ecql_frame:serialize(Frame),
                    ?LOG(Logger, debug, "SEND: ~p", [Data]),
                    ecql_sock:send(Sock, Data)
            end,
            ProtoState = ecql_proto:init(SendFun),
            {ok, State#state{socket = Sock, receiver = Receiver, proto_state = ProtoState}};
        {error, Reason} ->
            {error, Reason}
    end.

reply(Call, Reply, Callers) ->
    lists:foldl(fun({Call0, From}, Acc) when Call0 =:= Call ->
                    gen_fsm:reply(From, Reply), Acc;
                   (Caller, Acc) ->
                    [Caller|Acc]
                end, [], Callers).

received(Frame = ?ERROR_FRAME(#ecql_error{code = Code, message = Message}), State) ->
    response(ecql_frame:stream(Frame), {error, {Code, Message}}, State);

received(Frame = ?SUPPORTED_FRAME(Options), State) ->
    response(ecql_frame:stream(Frame), {ok, Options}, State);

received(Frame = ?RESULT_FRAME(void, _Any), State) ->
    response(ecql_frame:stream(Frame), ok, State);

received(Frame = ?RESULT_FRAME(rows, #ecql_rows{meta = Meta, data = Rows}), State) ->
    #ecql_rows_meta{columns = Columns, table_spec = TableSpec} = Meta,
    response(ecql_frame:stream(Frame), {ok, {TableSpec, Columns, Rows}}, State);

received(Frame = ?RESULT_FRAME(set_keyspace, #ecql_set_keyspace{keyspace = Keyspace}), State) ->
    response(ecql_frame:stream(Frame), {ok, Keyspace}, State);

received(Frame = ?RESULT_FRAME(prepared, #ecql_prepared{id = Id}), State) ->
    response(ecql_frame:stream(Frame), {ok, Id}, State);

received(Frame = ?RESULT_FRAME(schema_change, #ecql_schema_change{type = Type, target = Target, options = Options}), State) ->
    response(ecql_frame:stream(Frame), {ok, {Type, Target, Options}}, State);

received(Frame = ?RESULT_FRAME(_OpCode, Resp), State) ->
    response(ecql_frame:stream(Frame), {ok, Resp}, State).

response(StreamId, Response, State = #state{requests = Reqs}) ->
    case dict:find(StreamId, Reqs) of
        {ok, From} -> gen_fsm:reply(From, Response),
                      State#state{requests = dict:erase(StreamId, Reqs)};
        error      -> State
    end.

shutdown(Reason, State) ->
    {stop, {shutdown, Reason}, State}.

auth_token(undefined, undefined) ->
    <<0, 0>>;
auth_token(Username, undefined) ->
    <<0, Username/binary, 0>>;
auth_token(Username, Password) ->
    <<0, Username/binary, 0, Password/binary>>.

bin(undefined)           -> undefined;
bin(S) when is_list(S)   -> list_to_binary(S);
bin(B) when is_binary(B) -> B.

