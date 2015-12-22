
-module(ecql_proto).

-include("ecql.hrl").

-export([startup_frame/1, prepare_frame/2, query_frame/2, query_frame/3]).

startup_frame(StreamId) ->
    #ecql_frame{stream = StreamId, opcode = ?OP_STARTUP, req = #ecql_startup{}}.

prepare_frame(StreamId, Query) ->
    #ecql_frame{stream = StreamId, opcode = ?OP_PREPARE, req = #ecql_prepare{query = Query}}.

query_frame(StreamId, Query) ->
    #ecql_frame{stream = StreamId, opcode = ?OP_QUERY,
                req = #ecql_query{query = Query, parameters = #ecql_query_parameters{}}}.

query_frame(StreamId, Query, Values) ->
    Parameters = #ecql_query_parameters{values = Values},
    #ecql_frame{stream = StreamId, opcode = ?OP_QUERY,
                req = #ecql_query{query = Query, parameters = Parameters}}.

