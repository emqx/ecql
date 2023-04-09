%%-----------------------------------------------------------------------------
%% Copyright (c) 2015 Feng Lee <feng@emqtt.io>. All Rights Reserved.
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.

%%-----------------------------------------------------------------------------
%% @doc CQL Driver.
%%
%% @author Feng Lee <feng@emqtt.io>
%%-----------------------------------------------------------------------------

-module(ecql).

-behaviour(gen_fsm).

-include("ecql.hrl").

-include("ecql_types.hrl").

%% API Function Exports
-export([connect/0, connect/1, options/1,
         query/2, query/3, query/4,
         async_query/2, async_query/3, async_query/4,
         prepare/2, prepare/3, execute/2, execute/3, execute/4,
         async_execute/2, async_execute/3, async_execute/4,
         batch/2, batch/3,
         async_batch/2, async_batch/3,
         close/1]).

%% gen_fsm Function Exports
-export([startup/2, startup/3, waiting_for_ready/2, waiting_for_ready/3,
         waiting_for_auth/2, waiting_for_auth/3, established/2, established/3,
         disconnected/2, disconnected/3]).

-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

-type host() :: inet:ip_address() | inet:hostname().

-type option() :: {nodes,    [{host(), inet:port_number()}]}
                | {username, iolist()}
                | {password, iolist()}
                | {keyspace, iolist()}
                | {prepared, [{atom(), iolist()}]}
                | ssl | {ssl, [ssl:ssloption()]}
                | {timeout,  timeout()}.

-record(state, {nodes     :: [{host(), inet:port_number()}],
                username  :: binary(),
                password  :: binary(),
                keyspace  :: binary(),
                transport :: tcp | ssl,
                socket    :: inet:socket(),
                receiver  :: pid(),
                callers   :: list(),
                requests  :: dict:dict(),
                prepared  :: dict:dict(),
                ssl_opts  :: [ssl:ssl_option()],
                tcp_opts  :: [gen_tcp:connect_option()],
                compression :: boolean(),
                proto_state}).

-define(LOG(Level, Format, Args),
        logger:Level("[ecql~p] " ++ Format, [self() | Args])).

-define(PASSWORD_AUTHENTICATOR, <<"org.apache.cassandra.auth.PasswordAuthenticator">>).

-define(PREPARED(Id), (is_atom(Id) orelse is_binary(Id))).

-type prepared_id() :: atom() | binary().

-type query_string() :: string() | iodata().

-type cql_result() :: Keyspace :: binary()
                    | {TableSpec :: binary(), Columns :: [tuple()], Rows :: list()}
                    | {Type :: binary(), Target :: binary(), Options :: any()}.

-type batch() :: [batch_query()].
-type batch_query() :: {query_string() | prepared_id(), Values :: list()}.

-export_type([cql_result/0]).

%%%-----------------------------------------------------------------------------
%%% API Function Definitions
%%%-----------------------------------------------------------------------------

%% @doc Connect to cassandra.
-spec connect() -> {ok, pid()} | {error, any()}.
connect() -> connect([]).

-spec connect([option()]) -> {ok, pid()} | {error, any()}.
connect(Opts) when is_list(Opts) ->
    case gen_fsm:start_link(?MODULE, [Opts], []) of
        {ok, CPid}     -> connect(CPid);
        {error, Error} -> {error, Error}
    end;

connect(CPid) when is_pid(CPid) ->
    case gen_fsm:sync_send_event(CPid, connect) of
        ok     -> {ok, _} = set_keyspace(CPid),
                  {ok, CPid};
        Error -> Error
    end.

set_keyspace(CPid) -> gen_fsm:sync_send_event(CPid, set_keyspace).

%% @doc Options.
-spec options(pid()) -> {ok, list()} | {error, any()}.
options(CPid) ->
    gen_fsm:sync_send_all_state_event(CPid, options).

%% @doc Query.
-spec query(pid(), query_string()) -> {ok, cql_result()} | {error, any()}.
query(CPid, Query) ->
    gen_fsm:sync_send_event(CPid, {query, #ecql_query{query = iolist_to_binary(Query)}}).

-spec query(pid(), query_string(), list()) -> {ok, cql_result()} | {error, any()}.
query(CPid, Query, Values) when is_list(Values) ->
    query(CPid, Query, Values, one).

-spec query(pid(), query_string(), list(), atom()) -> {ok, cql_result()} | {error, any()}.
query(CPid, Query, Values, CL) when is_atom(CL) ->
    QObj = #ecql_query{query = iolist_to_binary(Query), consistency = ecql_cl:value(CL), values = Values},
    gen_fsm:sync_send_event(CPid,{query, QObj}).

%% @doc Query Asynchronously.
-spec async_query(pid(), query_string()) -> {ok, reference()} | {error, any()}.
async_query(CPid, Query) ->
    gen_fsm:sync_send_event(CPid, {async_query, #ecql_query{query = iolist_to_binary(Query)}}).

-spec async_query(pid(), query_string(), list()) -> {ok, reference()} | {error, any()}.
async_query(CPid, Query, Values) ->
    async_query(CPid, Query, Values, one).

-spec async_query(pid(), query_string(), list(), atom()) -> {ok, reference()} | {error, any()}.
async_query(CPid, Query, Values, CL) when is_atom(CL) ->
    QObj = #ecql_query{query = iolist_to_binary(Query),
                       consistency = ecql_cl:value(CL),
                       values = Values},
    gen_fsm:sync_send_event(CPid,{async_query, QObj}).

%% @doc Prepare.
-spec prepare(pid(), query_string()) -> {ok, binary()} | {error, any()}.
prepare(CPid, Query) ->
    gen_fsm:sync_send_event(CPid, {prepare, iolist_to_binary(Query)}).

%% @doc Named Prepare.
-spec prepare(pid(), Name :: atom(), query_string()) -> {ok, binary()} | {error, any()}.
prepare(CPid, Name, Query) ->
    gen_fsm:sync_send_event(CPid, {prepare, Name, iolist_to_binary(Query)}).

%% @doc Execute.
-spec execute(pid(), prepared_id()) -> {ok, cql_result()} | {error, any()}.
execute(CPid, Id) when ?PREPARED(Id) ->
    gen_fsm:sync_send_event(CPid, {execute, Id, #ecql_query{}}).

-spec execute(pid(), prepared_id(), list()) -> {ok, cql_result()} | {error, any()}.
execute(CPid, Id, Values) when ?PREPARED(Id) andalso is_list(Values) ->
    execute(CPid, Id, Values, one).

-spec execute(pid(), prepared_id(), list(), atom()) -> {ok, cql_result()} | {error, any()}.
execute(CPid, Id, Values, CL) when ?PREPARED(Id) andalso is_atom(CL) ->
    QObj = #ecql_query{consistency = ecql_cl:value(CL), values = Values},
    gen_fsm:sync_send_event(CPid, {execute, Id, QObj}).

%% @doc Execute Asynchronously.
-spec async_execute(pid(), prepared_id()) -> {ok, reference()} | {error, any()}.
async_execute(CPid, Id) when ?PREPARED(Id) ->
    gen_fsm:sync_send_event(CPid, {async_execute, Id, #ecql_query{}}).

-spec async_execute(pid(), prepared_id(), list()) -> {ok, reference()} | {error, any()}.
async_execute(CPid, Id, Values) when ?PREPARED(Id) andalso is_list(Values) ->
    async_execute(CPid, Id, Values, one).

-spec async_execute(pid(), prepared_id(), list(), atom()) -> {ok, reference()} | {error, any()}.
async_execute(CPid, Id, Values, CL) when ?PREPARED(Id) andalso is_atom(CL) ->
    QObj = #ecql_query{consistency = ecql_cl:value(CL), values = Values},
    gen_fsm:sync_send_event(CPid, {async_execute, Id, QObj}).

-spec batch(pid(), batch()) -> ok | {error, any()}.
batch(CPid, Queries) ->
    batch(CPid, Queries, one).

-spec batch(pid(), batch(), atom()) -> ok | {error, any()}.
batch(CPid, Queries, CL) when is_atom(CL) ->
    QObj = #ecql_batch{queries = Queries, consistency = ecql_cl:value(CL)},
    gen_fsm:sync_send_event(CPid, {batch, QObj}).

-spec async_batch(pid(), batch()) -> {ok, reference()} | {error, any()}.
async_batch(CPid, Queries) ->
    async_batch(CPid, Queries, one).

-spec async_batch(pid(), batch(), atom()) -> {ok, reference()} | {error, any()}.
async_batch(CPid, Queries, CL) when is_atom(CL) ->
    QObj = #ecql_batch{queries = Queries, consistency = ecql_cl:value(CL)},
    gen_fsm:sync_send_event(CPid, {async_batch, QObj}).

%% @doc Close the client.
-spec close(pid()) -> ok.
close(CPid) -> gen_fsm:sync_send_all_state_event(CPid, close).

%%%-----------------------------------------------------------------------------
%%% gen_fsm Function Definitions
%%%-----------------------------------------------------------------------------

init([Opts]) ->
    State = #state{nodes     = [{"127.0.0.1", 9042}],
                   callers   = [],
                   requests  = dict:new(),
                   prepared  = dict:new(),
                   transport = tcp,
                   tcp_opts  = [],
                   ssl_opts  = []},
    {ok, startup, init_opt(Opts, State)}.

init_opt([], State) ->
    State;
init_opt([{nodes, Nodes} | Opts], State) ->
    init_opt(Opts, State#state{nodes = Nodes});
init_opt([{username, Username}| Opts], State) ->
    init_opt(Opts, State#state{username = iolist_to_binary(Username)});
init_opt([{password, Password}| Opts], State) ->
    init_opt(Opts, State#state{password = iolist_to_binary(Password)});
init_opt([{keyspace, Keyspace}| Opts], State) ->
    init_opt(Opts, State#state{keyspace = iolist_to_binary(Keyspace)});
init_opt([ssl | Opts], State) ->
    ssl:start(), % ok?
    init_opt(Opts, State#state{transport = ssl});
init_opt([{ssl, SslOpts} | Opts], State) ->
    ssl:start(), % ok?
    init_opt(Opts, State#state{transport = ssl, ssl_opts = SslOpts});
init_opt([{tcp_opts, TcpOpts} | Opts], State) ->
    init_opt(Opts, State#state{tcp_opts = TcpOpts});
init_opt([_Opt | Opts], State) ->
    init_opt(Opts, State).

startup(Event, State) ->
    ?LOG(error, "[startup]: Unexpected Event: ~p", [Event]),
    {next_state, startup, State}.

startup(connect, From, State = #state{callers = Callers}) ->
    case connect_cassa(State) of
        {ok, NewState = #state{proto_state = ProtoState}} ->
            {_, NewProto} = ecql_proto:startup(ProtoState),
            {next_state, waiting_for_ready, NewState#state{
                    callers = [{connect, From}|Callers], proto_state = NewProto}};
        Error ->
            {stop, Error, Error, State}
    end.

waiting_for_ready(?READY_FRAME, State = #state{callers = Callers}) ->
    next_state(established, State#state{callers = reply(connect, ok, Callers)});

waiting_for_ready(?RESP_FRAME(?OP_ERROR, #ecql_error{code = Code, message = Message}), State = #state{callers = Callers}) ->
    shutdown(ecql_error, State#state{callers = reply(connect, {error, {Code, Message}}, Callers)});

waiting_for_ready(?RESP_FRAME(StreamId, ?OP_AUTHENTICATE, #ecql_authenticate{class = ?PASSWORD_AUTHENTICATOR}),
                  State = #state{username = Username, password = Password, proto_state = ProtoState}) ->
    Token = auth_token(Username, Password),
    {_Frame, NewProtoState} = ecql_proto:auth_response(StreamId, Token, ProtoState),
    next_state(waiting_for_auth, State#state{proto_state = NewProtoState});

waiting_for_ready(?RESP_FRAME(?OP_AUTHENTICATE, #ecql_authenticate{class = Class}),
                  State = #state{callers = Callers}) ->
    reply(connect, {error, {unsupported_auth_class, Class}}, Callers),
    shutdown({auth_error, Class}, State);

waiting_for_ready(Event, State) ->
    ?LOG(error, "Uexpected Event(waiting_for_ready): ~p", [Event]),
    next_state(waiting_for_ready, State).

waiting_for_ready(_Event, _From, State) ->
    {reply, {error, waiting_for_ready}, waiting_for_ready, State}.

waiting_for_auth(?RESP_FRAME(?OP_AUTH_CHALLENGE, #ecql_auth_challenge{token = Token}),
                 State = #state{callers = Callers}) ->
    ?LOG(error, "Auth Challenge: ~p", [Token]),
    shutdown(password_error, State#state{callers = reply(connect, {error, password_error}, Callers)});

waiting_for_auth(?RESP_FRAME(?OP_AUTH_SUCCESS, #ecql_auth_success{token = Token}),
                 State = #state{callers = Callers}) ->
    ?LOG(info, "Auth Success: ~p", [Token]),
    next_state(established, State#state{callers = reply(connect, ok, Callers)});

waiting_for_auth(?RESP_FRAME(?OP_ERROR, #ecql_error{message = Message}),
                 State = #state{callers = Callers}) ->
    Callers1 = reply(connect, {error, {auth_failed, Message}}, Callers),
    shutdown(auth_error, State#state{callers = Callers1});

waiting_for_auth(Event, State) ->
    ?LOG(error, "Unexpected Event(waiting_for_auth): ~p", [Event]),
    next_state(waiting_for_auth, State).

waiting_for_auth(_Event, _From, State) ->
    {reply, {error, waiting_for_auth}, waiting_for_auth, State}.

established(Frame, State)
        when is_record(Frame, ecql_frame) ->
    ?LOG(info, "Frame ~p", [Frame]),
    NewState = received(Frame, State),
    next_state(established, NewState);

established(Event, State) ->
    ?LOG(error, "Unexpected Event(established): ~p", [Event]),
    next_state(established, State).

established(set_keyspace, _From, State = #state{keyspace = undefined}) ->
    {reply, {ok, undefined}, established, State};

established(set_keyspace, From, State = #state{keyspace = Keyspace}) ->
    Query = #ecql_query{query = <<"use ", Keyspace/binary>>},
    established({query, Query}, From, State);

established({query, Query}, From, State = #state{proto_state = ProtoSate})
        when is_record(Query, ecql_query) ->
    request(From, fun ecql_proto:query/2, [Query, ProtoSate], State);

established({async_query, Query}, From, State = #state{proto_state = ProtoSate}) ->
    AsyncRef = make_ref(),
    {_, _, NewState} = request({async, AsyncRef, From}, fun ecql_proto:query/2, [Query, ProtoSate], State),
    {reply, {ok, AsyncRef}, established, NewState};

established({prepare, Query}, From, State = #state{proto_state = ProtoSate}) ->
    request(From, fun ecql_proto:prepare/2, [Query, ProtoSate], State);

established({prepare, Name, Query}, From, State = #state{requests = Reqs,
                                                         prepared = Prepared,
                                                         proto_state = ProtoSate}) ->
    case dict:find(Name, Prepared) of
        {ok, Id} ->
            %%TODO: unprepare?
            {reply, {ok, Id}, established, State};
        error ->
            {Frame, ProtoState} = ecql_proto:prepare(Query, ProtoSate),
            StreamId = ecql_frame:stream(Frame),
            NewState = State#state{proto_state = ProtoState,
                                   prepared    = dict:store({pending, StreamId}, Name, Prepared),
                                   requests    = dict:store(StreamId, From, Reqs)},
            {next_state, established, NewState}
    end;

established({execute, Name, Query}, From, State = #state{prepared = Prepared}) when is_atom(Name) ->
    case dict:find(Name, Prepared) of
        {ok, Id} ->
            established({execute, Id, Query}, From, State);
        error ->
            {reply, {error, not_prepared}, established, State}
    end;

established({execute, Id, Query}, From, State = #state{proto_state = ProtoSate}) when is_binary(Id) ->
    request(From, fun ecql_proto:execute/3, [Id, Query, ProtoSate], State);

established({async_executue, Id, Query}, From, State = #state{proto_state = ProtoSate}) ->
    AsyncRef = make_ref(),
    {_, _, NewState} = request({async, AsyncRef, From}, fun ecql_proto:execute/3,
                               [Id, Query, ProtoSate], State),
    {reply, {ok, AsyncRef}, established, NewState};

established({batch, Query}, From, State = #state{prepared = Prepared, proto_state = ProtoSate})
        when is_record(Query, ecql_batch) ->
    Queries = pre_format_queries(Query#ecql_batch.queries, Prepared),
    request(From, fun ecql_proto:batch/2, [Query#ecql_batch{queries = Queries}, ProtoSate], State);

established({async_batch, Query}, From, State = #state{prepared = Prepared, proto_state = ProtoSate})
        when is_record(Query, ecql_batch) ->
    AsyncRef = make_ref(),
    Queries = pre_format_queries(Query#ecql_batch.queries, Prepared),
    {_, _, NewState} = request({async, AsyncRef, From}, fun ecql_proto:batch/2,
                               [Query#ecql_batch{queries = Queries}, ProtoSate], State),
    {reply, {ok, AsyncRef}, established, NewState};

established(_Event, _From, State) ->
    {reply, {error, unsupported}, established, State}.

request(From, Fun, Args, State = #state{requests = Reqs}) ->
    {Frame, ProtoState} = apply(Fun, Args),
    {next_state, established, State#state{proto_state = ProtoState,
            requests = dict:store(ecql_frame:stream(Frame), From, Reqs)}}.

disconnected(Event, State) ->
    ?LOG(error, "Unexpected Event(disconnected): ~p", [Event]),
    {next_state, disconnected, State}.

disconnected(_Event, _From, State) ->
    {reply, {error, disconnected}, disconnected, State}.

handle_event({frame_error, Error}, _StateName, State) ->
    ?LOG(error, "Frame Error: ~p", [Error]),
    shutdown({frame_error, Error}, State);

handle_event({connection_lost, Reason}, _StateName, State) ->
    ?LOG(warning, "Connection lost for: ~p", [Reason]),
     shutdown(Reason, State#state{socket = undefined, receiver = undefined});

handle_event(Event, StateName, State) ->
    ?LOG(error, "Unexpected Event(~s): ~p", [StateName, Event]),
    next_state(StateName, State).

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

handle_sync_event(close, _From, _StateName, State) ->
    {stop, normal, ok, State};

handle_sync_event(_Event, _From, StateName, State) ->
    {reply, {error, StateName}, StateName, State}.

handle_info(Info, StateName, State) ->
    ?LOG(error, "Unexpected Info(~s): ~p", [StateName, Info]),
    next_state(StateName, State).

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%-----------------------------------------------------------------------------
%%% Internal Function Definitions
%%%-----------------------------------------------------------------------------

connect_cassa(State = #state{nodes     = Nodes,
                             transport = Transport,
                             tcp_opts  = TcpOpts,
                             ssl_opts  = SslOpts}) ->
    {Host, Port} = lists:nth(crypto:rand_uniform(1, length(Nodes) + 1), Nodes),
    ?LOG(info, "connecting to ~s:~p", [Host, Port]),
    case ecql_sock:connect(self(), Transport, Host, Port, TcpOpts, SslOpts) of
        {ok, Sock, Receiver} ->
            ?LOG(info, "connected with ~s:~p", [Host, Port]),
            SendFun = fun(Frame) ->
                    Data = ecql_frame:serialize(Frame),
                    ?LOG(debug, "SEND: ~p", [Data]),
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

received(Frame = ?RESULT_FRAME(prepared, #ecql_prepared{id = Id}), State = #state{prepared = Prepared}) ->
    PendingKey = {pending, ecql_frame:stream(Frame)},
    Prepared1 = case dict:find(PendingKey, Prepared) of
                    {ok, Name} -> dict:store(Name, Id, dict:erase(PendingKey, Prepared));
                    error      -> Prepared
                end,
    response(ecql_frame:stream(Frame), {ok, Id}, State#state{prepared = Prepared1});

received(Frame = ?RESULT_FRAME(schema_change, #ecql_schema_change{type = Type, target = Target, options = Options}), State) ->
    response(ecql_frame:stream(Frame), {ok, {Type, Target, Options}}, State);

received(Frame = ?RESULT_FRAME(_OpCode, Resp), State) ->
    response(ecql_frame:stream(Frame), {ok, Resp}, State).

response(StreamId, Response, State = #state{requests = Reqs}) ->
    case dict:find(StreamId, Reqs) of
        {ok, {async, Ref, {From, _}}} ->
            From ! {async_cql_reply, Ref, Response},
            State#state{requests = dict:erase(StreamId, Reqs)};
        {ok, From} ->
            gen_fsm:reply(From, Response),
            State#state{requests = dict:erase(StreamId, Reqs)};
        error ->
            State
    end.

shutdown(Reason, State) ->
    {stop, {shutdown, Reason}, State}.

next_state(StateName, State) ->
    {next_state, StateName, State, hibernate}.

auth_token(undefined, undefined) ->
    <<0, 0>>;
auth_token(Username, undefined) ->
    <<0, Username/binary, 0>>;
auth_token(Username, Password) ->
    <<0, Username/binary, 0, Password/binary>>.

pre_format_queries(Queries, Prepared) ->
    lists:map(fun({QueryOrId, Values}) ->
        {Kind, QueryOrId1} =
            case dict:find(QueryOrId, Prepared) of
                {ok, Id} -> {?BATCH_QUERY_KIND_PREPARED_ID, Id};
                error -> {?BATCH_QUERY_KIND_NORMAL_QUERY, iolist_to_binary(QueryOrId)}
            end,
        #ecql_batch_query{kind = Kind, query_or_id = QueryOrId1, values = Values}
    end, Queries).
