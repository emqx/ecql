%%-----------------------------------------------------------------------------
%% Copyright (c) 2015-2024 Feng Lee <feng@emqtt.io>. All Rights Reserved.
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
-behaviour(gen_statem).

-include("ecql.hrl").
-include("ecql_types.hrl").

%% API Function Exports
-export([connect/0, connect/1, options/1,
         query/2, query/3, query/4,
         async_query/2, async_query/3, async_query/4, async_query/5,
         prepare/2, prepare/3, execute/2, execute/3, execute/4,
         async_execute/2, async_execute/3, async_execute/4,
         batch/2, batch/3,
         async_batch/2, async_batch/3, async_batch/4,
         close/1]).

%% gen_statem Function Exports
-export([startup/3, waiting_for_ready/3, waiting_for_auth/3, established/3, disconnected/3]).

-export([callback_mode/0, init/1, terminate/3, code_change/4]).

%% internal exports
-export([default_response_callback/3]).

-type host() :: inet:ip_address() | inet:hostname().

-type option() :: {nodes,    [{host(), inet:port_number()}]}
                | {username, iolist()}
                | {password, iolist()}
                | {keyspace, iolist()}
                | {prepared, [{atom(), iolist()}]}
                | ssl | {ssl, [ssl:ssloption()]}
                | {timeout,  timeout()}.

-record(state, {nodes     :: [{host(), inet:port_number()}],
                username  :: undefined | binary(),
                password  :: ecql_secret:t(undefined | binary()),
                keyspace  :: undefined | binary(),
                transport :: tcp | ssl,
                socket    :: undefined | inet:socket(),
                receiver  :: undefined | pid(),
                callers   = [] :: list(),
                requests  :: dict:dict(),
                prepared  :: dict:dict(),
                ssl_opts  :: [ssl:ssl_option()],
                tcp_opts  :: [gen_tcp:connect_option()],
                compression = false :: boolean(),
                proto_state}).

-define(LOG(Level, Format, Args),
        logger:Level("[ecql~p] " ++ Format, [self() | Args])).

-define(PASSWORD_AUTHENTICATOR, <<"org.apache.cassandra.auth.PasswordAuthenticator">>).

-define(PREPARED_STMT_ID(ID), {prepared_stmt_id, ID}).

-type prepared_stmt_id() :: ?PREPARED_STMT_ID(binary()).

-type prepared_key() :: term().

-type prepared_id() :: atom() | binary() | prepared_stmt_id().

-type query_string() :: string() | iodata().

-type cql_result() :: Keyspace :: binary()
                    | {TableSpec :: binary(), Columns :: [tuple()], Rows :: list()}
                    | {Type :: binary(), Target :: binary(), Options :: any()}.

-type batch() :: [batch_query()].
-type batch_query() :: {query_string() | prepared_id(), Values :: list()}.

-type callback() :: function()
                  | {function(), Args :: list()}
                  | {module(), function(), Args :: list()}
                  | undefined
                  | default_async_callback.

-export_type([cql_result/0]).

%%%-----------------------------------------------------------------------------
%%% API Function Definitions
%%%-----------------------------------------------------------------------------

%% @doc Connect to cassandra.
-spec connect() -> {ok, pid()} | {error, any()}.
connect() -> connect([]).

-spec connect([option()] | pid()) -> {ok, pid()} | {error, any()}.
connect(Opts) when is_list(Opts) ->
    case gen_statem:start_link(?MODULE, [Opts], []) of
        {ok, CPid}     -> connect(CPid);
        {error, Error} -> {error, Error}
    end;

connect(CPid) when is_pid(CPid) ->
    case gen_statem:call(CPid, connect) of
        ok     -> {ok, _} = set_keyspace(CPid),
                  {ok, CPid};
        Error -> Error
    end.

set_keyspace(CPid) -> gen_statem:call(CPid, set_keyspace).

%% @doc Options.
-spec options(pid()) -> {ok, list()} | {error, any()}.
options(CPid) ->
    gen_statem:call(CPid, options).

%% @doc Query.
-spec query(pid(), query_string()) -> {ok, cql_result()} | {error, any()}.
query(CPid, Query) ->
    gen_statem:call(CPid, {query, #ecql_query{query = iolist_to_binary(Query)}}).

-spec query(pid(), query_string(), list()) -> {ok, cql_result()} | {error, any()}.
query(CPid, Query, Values) when is_list(Values) ->
    query(CPid, Query, Values, one).

-spec query(pid(), query_string(), list(), atom()) -> {ok, cql_result()} | {error, any()}.
query(CPid, Query, Values, CL) when is_atom(CL) ->
    QObj = #ecql_query{query = iolist_to_binary(Query), consistency = ecql_cl:value(CL), values = Values},
    gen_statem:call(CPid,{query, QObj}).

%% @doc Query Asynchronously.
-spec async_query(pid(), query_string()) -> ok | {ok, reference()} | {error, any()}.
async_query(CPid, Query) ->
    gen_statem:call(
      CPid,
      {async_query, #ecql_query{query = iolist_to_binary(Query)}, default_async_callback}
     ).

-spec async_query(pid(), query_string(), list()) -> ok | {ok, reference()} | {error, any()}.
async_query(CPid, Query, Values) ->
    async_query(CPid, Query, Values, one, default_async_callback).

-spec async_query(pid(), query_string(), list(), atom() | callback()) -> ok | {ok, reference()} | {error, any()}.
async_query(CPid, Query, Values, CL) when is_atom(CL) ->
    async_query(CPid, Query, Values, CL, default_async_callback);
async_query(CPid, Query, Values, Callback) ->
    async_query(CPid, Query, Values, one, Callback).

-spec async_query(pid(), query_string(), list(), atom(), callback()) -> ok | {ok, reference()} | {error, any()}.
async_query(CPid, Query, Values, CL, Callback) when is_atom(CL) ->
    QObj = #ecql_query{query = iolist_to_binary(Query),
                       consistency = ecql_cl:value(CL),
                       values = Values},
    gen_statem:call(CPid,{async_query, QObj, Callback}).

%% @doc Prepare.
-spec prepare(pid(), query_string()) -> {ok, prepared_stmt_id()} | {error, any()}.
prepare(CPid, Query) ->
    gen_statem:call(CPid, {prepare, iolist_to_binary(Query)}).

%% @doc Named Prepare.
-spec prepare(pid(), prepared_key(), query_string()) -> {ok, prepared_stmt_id()} | {error, any()}.
prepare(CPid, PreparedKey, Query) ->
    gen_statem:call(CPid, {prepare, PreparedKey, iolist_to_binary(Query)}).

%% @doc Execute.
-spec execute(pid(), prepared_id()) -> {ok, cql_result()} | {error, any()}.
execute(CPid, Id) ->
    gen_statem:call(CPid, {execute, Id, #ecql_query{}}).

-spec execute(pid(), prepared_id(), list()) -> {ok, cql_result()} | {error, any()}.
execute(CPid, Id, Values) when is_list(Values) ->
    execute(CPid, Id, Values, one).

-spec execute(pid(), prepared_id(), list(), atom()) -> {ok, cql_result()} | {error, any()}.
execute(CPid, Id, Values, CL) when is_atom(CL) ->
    QObj = #ecql_query{consistency = ecql_cl:value(CL), values = Values},
    gen_statem:call(CPid, {execute, Id, QObj}).

%% @doc Execute Asynchronously.
-spec async_execute(pid(), prepared_id()) -> ok | {ok, reference()} | {error, any()}.
async_execute(CPid, Id) ->
    gen_statem:call(CPid, {async_execute, Id, #ecql_query{}, default_async_callback}).

-spec async_execute(pid(), prepared_id(), list()) -> ok | {ok, reference()} | {error, any()}.
async_execute(CPid, Id, Values) when is_list(Values) ->
    async_execute(CPid, Id, Values, one).

-spec async_execute(pid(), prepared_id(), list(), atom() | callback()) -> ok | {ok, reference()} | {error, any()}.
async_execute(CPid, Id, Values, CL) when is_atom(CL) ->
    async_execute(CPid, Id, Values, CL, default_async_callback);
async_execute(CPid, Id, Values, Callback) ->
    async_execute(CPid, Id, Values, one, Callback).

-spec async_execute(pid(), prepared_id(), list(), atom(), callback()) -> ok | {ok, reference()} | {error, any()}.
async_execute(CPid, Id, Values, CL, Callback) when is_atom(CL) ->
    QObj = #ecql_query{consistency = ecql_cl:value(CL), values = Values},
    gen_statem:call(CPid, {async_execute, Id, QObj, Callback}).

-spec batch(pid(), batch()) -> ok | {error, any()}.
batch(CPid, Queries) ->
    batch(CPid, Queries, one).

%% @doc only UPDATE, INSERT and DELETE statements are allowed
-spec batch(pid(), batch(), atom()) -> ok | {error, any()}.
batch(CPid, Queries, CL) when is_atom(CL) ->
    QObj = #ecql_batch{queries = Queries, consistency = ecql_cl:value(CL)},
    gen_statem:call(CPid, {batch, QObj}).

-spec async_batch(pid(), batch()) -> ok | {ok, reference()} | {error, any()}.
async_batch(CPid, Queries) ->
    async_batch(CPid, Queries, one, default_async_callback).

-spec async_batch(pid(), batch(), atom() | callback()) -> ok | {ok, reference()} | {error, any()}.
async_batch(CPid, Queries, CL) when is_atom(CL) ->
    async_batch(CPid, Queries, CL, default_async_callback);
async_batch(CPid, Queries, Callback) ->
    async_batch(CPid, Queries, one, Callback).

-spec async_batch(pid(), batch(), atom(), callback()) -> ok | {ok, reference()} | {error, any()}.
async_batch(CPid, Queries, CL, Callback) when is_atom(CL) ->
    QObj = #ecql_batch{queries = Queries, consistency = ecql_cl:value(CL)},
    gen_statem:call(CPid, {async_batch, QObj, Callback}).

%% @doc Close the client.
-spec close(pid()) -> ok.
close(CPid) -> gen_statem:stop(CPid).

%%%-----------------------------------------------------------------------------
%%% gen_statem Callback Function Definitions
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

callback_mode() -> state_functions.

init_opt([], State) ->
    State;
init_opt([{nodes, Nodes} | Opts], State) ->
    init_opt(Opts, State#state{nodes = Nodes});
init_opt([{username, Username}| Opts], State) ->
    init_opt(Opts, State#state{username = iolist_to_binary(Username)});
init_opt([{password, Password}| Opts], State) ->
    init_opt(Opts, State#state{password = ecql_secret:wrap(iolist_to_binary(Password))});
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

startup(cast, Event, State) ->
    ?LOG(error, "[startup]: Unexpected Event: ~p", [Event]),
    {keep_state, State};

startup({call, From}, connect, State = #state{callers = Callers}) ->
    case connect_cassa(State) of
        {ok, NewState = #state{proto_state = ProtoState}} ->
            {_, NewProto} = ecql_proto:startup(ProtoState),
            {next_state, waiting_for_ready, NewState#state{
                    callers = [{connect, From}|Callers], proto_state = NewProto}};
        Error ->
            {stop, Error, State}
    end.

waiting_for_ready(cast, ?READY_FRAME, State = #state{callers = Callers}) ->
    {next_state, established, State#state{callers = reply(connect, ok, Callers)}};

waiting_for_ready(cast, ?RESP_FRAME(?OP_ERROR, #ecql_error{code = Code, message = Message}), State = #state{callers = Callers}) ->
    shutdown(ecql_error, State#state{callers = reply(connect, {error, {Code, Message}}, Callers)});

waiting_for_ready(cast, ?RESP_FRAME(StreamId, ?OP_AUTHENTICATE, #ecql_authenticate{class = ?PASSWORD_AUTHENTICATOR}),
                  State = #state{username = Username, password = Password, proto_state = ProtoState}) ->
    %% The token also is plain, hence needs to wrap too
    Token = ecql_secret:map(fun(Pw) -> auth_token(Username, Pw) end, Password),
    {_Frame, NewProtoState} = ecql_proto:auth_response(StreamId, Token, ProtoState),
    {next_state, waiting_for_auth, State#state{proto_state = NewProtoState}};

waiting_for_ready(cast, ?RESP_FRAME(?OP_AUTHENTICATE, #ecql_authenticate{class = Class}),
                  State = #state{callers = Callers}) ->
    reply(connect, {error, {unsupported_auth_class, Class}}, Callers),
    shutdown({auth_error, Class}, State);

waiting_for_ready(cast, Event, State) ->
    ?LOG(error, "Uexpected Event(waiting_for_ready): ~p", [Event]),
    {keep_state, State};

waiting_for_ready({call, From}, options, State) ->
    options(From, State);

waiting_for_ready({call, From}, _Event, State) ->
    {keep_state, State, [{reply, From, {error, waiting_for_ready}}]}.

waiting_for_auth(cast, ?RESP_FRAME(?OP_AUTH_CHALLENGE, #ecql_auth_challenge{token = Token}),
                 State = #state{callers = Callers}) ->
    ?LOG(error, "Auth Challenge: ~p", [Token]),
    shutdown(password_error, State#state{callers = reply(connect, {error, password_error}, Callers)});

waiting_for_auth(cast, ?RESP_FRAME(?OP_AUTH_SUCCESS, #ecql_auth_success{token = _Token}),
                 State = #state{callers = Callers}) ->
    ?LOG(info, "Auth Success: ~p", [<<"******">>]),
    {next_state, established, State#state{callers = reply(connect, ok, Callers)}};

waiting_for_auth(cast, ?RESP_FRAME(?OP_ERROR, #ecql_error{message = Message}),
                 State = #state{callers = Callers}) ->
    Callers1 = reply(connect, {error, {auth_failed, Message}}, Callers),
    shutdown(auth_error, State#state{callers = Callers1});

waiting_for_auth(cast, Event, State) ->
    ?LOG(error, "Unexpected Event(waiting_for_auth): ~p", [Event]),
    {keep_state, State};

waiting_for_auth({call, From}, options, State) ->
    options(From, State);

waiting_for_auth({call, From}, _Event, State) ->
    {keep_state, State, [{reply, From, {error, waiting_for_auth}}]}.

established(cast, Frame, State)
        when is_record(Frame, ecql_frame) ->
    ?LOG(info, "Frame ~p", [Frame]),
    NewState = received(Frame, State),
    {keep_state, NewState};

established(cast, Event, State) ->
    ?LOG(error, "Unexpected Event(established): ~p", [Event]),
    {keep_state, State};

established({call, From}, set_keyspace, State = #state{keyspace = undefined}) ->
    {keep_state, State, [{reply, From, {ok, undefined}}]};

established({call, From}, set_keyspace, State = #state{keyspace = Keyspace}) ->
    Query = #ecql_query{query = <<"use ", Keyspace/binary>>},
    established({call, From}, {query, Query}, State);

established({call, From}, {query, Query}, State = #state{proto_state = ProtoSate})
        when is_record(Query, ecql_query) ->
    request(From, fun ecql_proto:query/2, [Query, ProtoSate], State);

established({call, From}, {async_query, Query, Callback}, State = #state{proto_state = ProtoSate}) ->
    {Reply, Callback1} = make_callback(Callback, From),
    {_, _, NewState} = request({async, Callback1}, fun ecql_proto:query/2, [Query, ProtoSate], State),
    {keep_state, NewState, [{reply, From, Reply}]};

established({call, From}, {prepare, Query}, State = #state{proto_state = ProtoSate}) ->
    request(From, fun ecql_proto:prepare/2, [Query, ProtoSate], State);

established({call, From}, {prepare, PreparedKey, Query}, State = #state{requests = Reqs,
                                                                        prepared = Prepared,
                                                                        proto_state = ProtoSate}) ->
    case dict:find(PreparedKey, Prepared) of
        {ok, Id} ->
            %%TODO: unprepare?
            {keep_state, State, [{reply, From, {ok, Id}}]};
        error ->
            {Frame, ProtoState} = ecql_proto:prepare(Query, ProtoSate),
            StreamId = ecql_frame:stream(Frame),
            NewState = State#state{proto_state = ProtoState,
                                   prepared    = dict:store({pending, StreamId}, PreparedKey, Prepared),
                                   requests    = dict:store(StreamId, From, Reqs)},
            {keep_state, NewState}
    end;

established({call, From}, {execute, ?PREPARED_STMT_ID(Id), Query}, State = #state{proto_state = ProtoSate}) ->
    request(From, fun ecql_proto:execute/3, [Id, Query, ProtoSate], State);

established({call, From}, {execute, PreparedKey, Query}, State = #state{prepared = Prepared}) ->
    case dict:find(PreparedKey, Prepared) of
        {ok, Id} ->
            established({call, From}, {execute, ?PREPARED_STMT_ID(Id), Query}, State);
        error ->
            {keep_state, State, [{reply, From, {error, not_prepared}}]}
    end;

established({call, From}, {async_execute, ?PREPARED_STMT_ID(Id), Query, Callback}, State = #state{proto_state = ProtoSate})
  when is_binary(Id) ->
    {Reply, Callback1} = make_callback(Callback, From),
    {_, _, NewState} = request({async, Callback1}, fun ecql_proto:execute/3,
                               [Id, Query, ProtoSate], State),
    {keep_state, NewState, [{reply, From, Reply}]};

established({call, From}, {async_execute, PreparedKey, Query, Callback}, State = #state{prepared = Prepared}) ->
    case dict:find(PreparedKey, Prepared) of
        {ok, Id} ->
            established({call, From}, {async_execute, ?PREPARED_STMT_ID(Id), Query, Callback}, State);
        error ->
            {keep_state, State, [{reply, From, {error, not_prepared}}]}
    end;

established({call, From}, {batch, Query}, State = #state{prepared = Prepared, proto_state = ProtoSate})
  when is_record(Query, ecql_batch) ->
    Queries = pre_format_queries(Query#ecql_batch.queries, Prepared),
    request(From, fun ecql_proto:batch/2, [Query#ecql_batch{queries = Queries}, ProtoSate], State);

established({call, From}, {async_batch, Query, Callback}, State = #state{prepared = Prepared, proto_state = ProtoSate})
  when is_record(Query, ecql_batch) ->
    Queries = pre_format_queries(Query#ecql_batch.queries, Prepared),
    {Reply, Callback1} = make_callback(Callback, From),
    {_, _, NewState} = request({async, Callback1}, fun ecql_proto:batch/2,
                               [Query#ecql_batch{queries = Queries}, ProtoSate], State),
    {keep_state, NewState, [{reply, From, Reply}]};

established({call, From}, options, State) ->
    options(From, State);

established({call, From}, _Event, State) ->
    {keep_state, State, [{reply, From, {error, unsupported}}]}.

request(From, Fun, Args, State = #state{requests = Reqs}) ->
    {Frame, ProtoState} = apply(Fun, Args),
    {next_state, established, State#state{proto_state = ProtoState,
                                          requests = dict:store(ecql_frame:stream(Frame), From, Reqs)}}.

disconnected(cast, Event, State) ->
    ?LOG(error, "Unexpected Event(disconnected): ~p", [Event]),
    {keep_state, State};

disconnected({call, From}, _Event, State) ->
    {keep_state, State, [{reply, From, {error, disconnected}}]}.

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
    {Host, Port} = lists:nth(rand:uniform(length(Nodes)), Nodes),
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
                    gen_statem:reply(From, Reply), Acc;
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
    Prepared1 =
        case dict:find(PendingKey, Prepared) of
            {ok, PreparedKey} ->
                dict:store(PreparedKey, Id, dict:erase(PendingKey, Prepared));
            error ->
                Prepared
        end,
    response(ecql_frame:stream(Frame), {ok, ?PREPARED_STMT_ID(Id)}, State#state{prepared = Prepared1});

received(Frame = ?RESULT_FRAME(schema_change, #ecql_schema_change{type = Type, target = Target, options = Options}), State) ->
    response(ecql_frame:stream(Frame), {ok, {Type, Target, Options}}, State);

received(Frame = ?RESULT_FRAME(_OpCode, Resp), State) ->
    response(ecql_frame:stream(Frame), {ok, Resp}, State).

response(StreamId, Response, State = #state{requests = Reqs}) ->
    case dict:find(StreamId, Reqs) of
        {ok, {async, Callback}} ->
            _ = apply_callback_function(Callback, Response),
            State#state{requests = dict:erase(StreamId, Reqs)};
        {ok, From} ->
            gen_statem:reply(From, Response),
            State#state{requests = dict:erase(StreamId, Reqs)};
        error ->
            State
    end.

shutdown(Reason, State) ->
    {stop, {shutdown, Reason}, State}.

auth_token(undefined, undefined) ->
    <<0, 0>>;
auth_token(Username, undefined) ->
    <<0, Username/binary, 0>>;
auth_token(Username, Password) ->
    <<0, Username/binary, 0, Password/binary>>.

pre_format_queries(Queries, Prepared) ->
    lists:map(fun
        ({?PREPARED_STMT_ID(Id), Values}) ->
            #ecql_batch_query{kind = ?BATCH_QUERY_KIND_PREPARED_ID, query_or_id = Id, values = Values};
        ({QueryOrPrepareKey, Values}) ->
            {Kind, QueryOrId1} =
                case dict:find(QueryOrPrepareKey, Prepared) of
                    {ok, Id} -> {?BATCH_QUERY_KIND_PREPARED_ID, Id};
                    error -> {?BATCH_QUERY_KIND_NORMAL_QUERY, iolist_to_binary(QueryOrPrepareKey)}
                end,
            #ecql_batch_query{kind = Kind, query_or_id = QueryOrId1, values = Values}
    end, Queries).

%% Result returned at the end of args
apply_callback_function(undefined, _Result) ->
    ok;
apply_callback_function(F, Result)
  when is_function(F) ->
    erlang:apply(F, [Result]);
apply_callback_function({F, A}, Result)
  when is_function(F),
       is_list(A) ->
    erlang:apply(F, A ++ [Result]);
apply_callback_function({M, F, A}, Result)
  when is_atom(M),
       is_atom(F),
       is_list(A) ->
    erlang:apply(M, F, A ++ [Result]).

make_callback(default_async_callback, {From, _}) ->
    Ref = make_ref(),
    {{ok, Ref}, {fun ?MODULE:default_response_callback/3, [From, Ref]}};
make_callback(Callback, _From) ->
    {ok, Callback}.

default_response_callback(From, Ref, Response) ->
    From ! {async_cql_reply, Ref, Response}.

options(From, State = #state{requests = Reqs,
                             proto_state = ProtoState}) ->
    {Frame, ProtoState1} = ecql_proto:options(ProtoState),
    Reqs1 = dict:store(ecql_frame:stream(Frame), From, Reqs),
    {keep_state, State#state{proto_state = ProtoState1,
                             requests    = Reqs1}}.
