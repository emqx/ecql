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
%%% @doc CQL Protocol.
%%%
%%% @author Feng Lee <feng@emqtt.io>
%%%-----------------------------------------------------------------------------

-module(ecql_proto).

-include("ecql.hrl").

-export([init/1, stream_id/1]).

-export([startup/1, startup/2, auth_response/3, options/1,
         prepare/2, query/2, query/3, query/4,
         execute/2, execute/3, execute/4,
         batch/2, register/2]).

-record(proto_state, {send_fun, stream_id}).

-type proto_state() :: #proto_state{}.

-spec init(SendFun :: fun((ecql_frame()) -> proto_state())) -> proto_state().
init(SendFun) ->
    #proto_state{send_fun = SendFun, stream_id = random:uniform(16#FF)}.

stream_id(#proto_state{stream_id = StreamId}) -> StreamId.

%% @doc startup frame
-spec startup(proto_state()) -> {ecql_frame(), proto_state()}.
startup(State) ->
    send_with_stream(?REQ_FRAME(?OP_STARTUP, #ecql_startup{}), State).

-spec startup(boolean(), proto_state()) -> {ecql_frame(), proto_state()}.
startup(Compression, State) ->
    send_with_stream(?REQ_FRAME(?OP_STARTUP, #ecql_startup{compression = Compression}), State).

%% @doc auth_response frame
-spec auth_response(stream_id(), binary(), proto_state()) -> {ecql_frame(), proto_state()}.
auth_response(StreamId, Token, State) ->
    Frame = ?REQ_FRAME(StreamId, ?OP_AUTH_RESPONSE, #ecql_auth_response{token = Token}),
    {Frame, send(Frame, State)}.

%% @doc options frame
-spec options(proto_state()) -> {stream_id(), proto_state()}.
options(State) ->
    send_with_stream(?REQ_FRAME(?OP_OPTIONS, #ecql_options{}), State).

%% @doc prepare frame
-spec prepare(binary(), proto_state()) -> {stream_id(), proto_state()}.
prepare(Query, State) when is_binary(Query) ->
    send_with_stream(?REQ_FRAME(?OP_PREPARE, #ecql_prepare{query = Query}), State).

%% @doc query frame
-spec query(binary() | ecql_query(), proto_state()) -> {ecql_frame(), proto_state()}.
query(Query, State) when is_record(Query, ecql_query) ->
    send_with_stream(?REQ_FRAME(?OP_QUERY, Query), State);

query(Query, State) when is_binary(Query) ->
    query(#ecql_query{query = Query}, State). 
    
-spec query(binary(), consistency(), proto_state()) -> {ecql_frame(), proto_state()}.
query(Query, CL, State) when ?IS_CL(CL) ->
    query(#ecql_query{query = Query, consistency = CL}, State).

-spec query(binary(), consistency(), list(), proto_state()) -> {ecql_frame(), proto_state()}.
query(Query, CL, Values, State) ->
    query(#ecql_query{query = Query, consistency = CL, values = Values}, State).

%% @doc execute frame
execute(Id, State) when is_binary(Id) ->
    send_with_stream(?REQ_FRAME(?OP_EXECUTE, #ecql_execute{id = Id}), State).

execute(Id, Query, State) when is_binary(Id) andalso is_record(Query, ecql_query) ->
    send_with_stream(?REQ_FRAME(?OP_EXECUTE, #ecql_execute{id = Id, query = Query}), State);

execute(Id, CL, State) when is_binary(Id) andalso ?IS_CL(CL) ->
    execute(Id, #ecql_query{consistency = CL}, State).

execute(Id, CL, Values, State) when is_binary(Id) andalso ?IS_CL(CL) ->
    execute(Id, #ecql_query{consistency = CL, values = Values}, State).

batch(_, _State) ->
    throw({error, batch_unsupported}).

-spec register(list(string()), proto_state()) -> {ecql_frame(), proto_state()}.
register(EventTypes, State) ->
    send_with_stream(?REQ_FRAME(?OP_REGISTER, #ecql_register{event_types = EventTypes}), State).

send_with_stream(Frame, State = #proto_state{stream_id = StreamId}) ->
    FrameWithStream = Frame#ecql_frame{stream = StreamId},
    {FrameWithStream, send(FrameWithStream, State)}.

send(Frame, State = #proto_state{send_fun = Send}) ->
    Send(Frame), next_stream_id(State).

next_stream_id(State = #proto_state{stream_id = 16#ffff}) ->
    State#proto_state{stream_id = 1};

next_stream_id(State = #proto_state{stream_id = Id}) ->
    State#proto_state{stream_id = Id + 1}.

