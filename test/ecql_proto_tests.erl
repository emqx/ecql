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

-module(ecql_proto_tests).

-ifdef(TEST).

-include("ecql.hrl").

-include_lib("eunit/include/eunit.hrl").

init() -> ecql_proto:init(fun(_) -> ok end).

startup_test() ->
    State = init(),
    Frame = ?REQ_FRAME(ecql_proto:stream_id(State), ?OP_STARTUP, #ecql_startup{}),
    ?assertMatch({Frame, _}, ecql_proto:startup(State)),

    Frame1 = ?REQ_FRAME(ecql_proto:stream_id(State), ?OP_STARTUP, #ecql_startup{compression = true}),
    ?assertMatch({Frame1, _}, ecql_proto:startup(true, State)).

auth_response_test() ->
    Frame = #ecql_frame{stream = 1, opcode = ?OP_AUTH_RESPONSE,
                        message = #ecql_auth_response{token = <<"token">>}},
    ?assertMatch({Frame, _}, ecql_proto:auth_response(1, <<"token">>, init())).

options_test() ->
    State = init(),
    Frame = #ecql_frame{stream = ecql_proto:stream_id(State),
                        opcode = ?OP_OPTIONS, message = #ecql_options{}},
    ?assertMatch({Frame, _}, ecql_proto:options(State)).

prepare_test() ->
    State = init(),
    Query = <<"select * from t">>,
    Frame = #ecql_frame{stream = ecql_proto:stream_id(State),
                        opcode = ?OP_PREPARE,
                        message = #ecql_prepare{query = Query}},
    ?assertMatch({Frame, _}, ecql_proto:prepare(Query, State)).

query_test() ->
    State = init(),
    Query = #ecql_query{query = <<"select * from x">>},
    FrameA = #ecql_frame{stream = ecql_proto:stream_id(State),
                         opcode = ?OP_QUERY,
                         message = Query},
    {Frame1, State1} = ecql_proto:query(Query, State),
    ?assertEqual(FrameA, Frame1),

    FrameB = #ecql_frame{stream = ecql_proto:stream_id(State1),
                         opcode = ?OP_QUERY,
                         message = #ecql_query{query = <<"select">>,
                                               consistency = ?CL_ONE}},
    {Frame2, State2} = ecql_proto:query(<<"select">>, ?CL_ONE, State1),
    ?assertEqual(FrameB, Frame2),

    FrameC = #ecql_frame{stream = ecql_proto:stream_id(State2),
                         opcode = ?OP_QUERY,
                         message = #ecql_query{query = <<"select">>,
                                               consistency = ?CL_ONE,
                                               values = [1,2,3]}},
    {Frame3, State3} = ecql_proto:query(<<"select">>, ?CL_ONE, [1,2,3], State2),
    ?assertEqual(FrameC, Frame3).

execute_test() ->
    State = init(),
    FrameA = #ecql_frame{stream = ecql_proto:stream_id(State),
                         opcode = ?OP_EXECUTE,
                         message = #ecql_execute{id = <<"abc">>}},

    {Frame1, State1} = ecql_proto:execute(<<"abc">>, State),
    ?assertEqual(FrameA, Frame1),

    FrameB = #ecql_frame{stream = ecql_proto:stream_id(State),
                         opcode = ?OP_EXECUTE,
                         message = #ecql_execute{id = <<"abc">>, query = #ecql_query{consistency = ?CL_TWO}}},

    {Frame2, State2} = ecql_proto:execute(<<"abc">>, ?CL_TWO, State),
    ?assertEqual(FrameB, Frame2).

register_test() ->
    State = init(),
    Frame = #ecql_frame{stream = ecql_proto:stream_id(State),
                        opcode = ?OP_REGISTER,
                        message = #ecql_register{event_types = [<<"SCHEMA_CHANGE">>]}},

    ?assertMatch({Frame, _}, ecql_proto:register([<<"SCHEMA_CHANGE">>], State)).

-endif.

