-module(ecql_proto).

-include("ecql.hrl").

-export([startup/1, query/2]).

startup(StreamId) ->
    ecql_frame:make(startup, StreamId).

query(StreamId, Query) ->
    #ecql_frame{stream = StreamId, opcode = ?OPCODE_QUERY,
                req = #ecql_query{query = Query, parameters = #ecql_query_parameters{}}}.

