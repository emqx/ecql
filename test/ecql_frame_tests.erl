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

-module(ecql_frame_tests).

-ifdef(TEST).

-include("ecql.hrl").

-include("ecql_types.hrl").

-include_lib("eunit/include/eunit.hrl").

-import(ecql_frame, [parser/0, serialize/1]).

ready_parse_test() ->
    Parser = parser(),
    {ok, #ecql_frame{stream = StreamId, message = Ready}, <<>>} = Parser(<<131,0,0,193,2,0,0,0,0>>),
    ?assertEqual(193, StreamId),
    ?assertEqual(#ecql_ready{}, Ready).

%% AUTHENTICATE Frame
auth_parse_test() ->
    Parser = parser(),
    {ok, #ecql_frame{stream = StreamId, message = Auth}, <<>>} = Parser(
                <<131,0,0,87,3,0,0,0,49,0,47,111,114,103,46,97,
                  112,97,99,104,101,46,99,97,115,115,97,110,100,
                  114,97,46,97,117,116,104,46,80,97,115,115,119,
                  111,114,100,65,117,116,104,101,110,116,105,99,
                  97,116,111,114>>),
    ?assertEqual(87, StreamId),
    ?assertEqual(#ecql_authenticate{class = <<"org.apache.cassandra.auth.PasswordAuthenticator">>}, Auth).


%%AUTH_SUCCESS FRAME
auth_sucess_parse_test() ->
    Parser = parser(),
    {ok, #ecql_frame{stream = 87, opcode = ?OP_AUTH_SUCCESS, message = AuthSucc}, <<>>}
        = Parser(<<131,0,0,87,16,0,0,0,4,255,255,255,255>>),
    ?assertEqual(#ecql_auth_success{token = <<>>}, AuthSucc).

%%SET_KEYSPACE Result FRAME
set_keyspace_result_parse_test() ->
    Parser = parser(),
    %%Set Keyspace Result
    {ok, #ecql_frame{stream = 194, opcode = ?OP_RESULT, message = #ecql_result{data = SetKeyspace}}, <<>>}
        = Parser(<<131,0,0,194,8,0,0,0,10,0,0,0,3,0,4,116,101,115, 116>>),
    ?assertEqual(#ecql_set_keyspace{keyspace = <<"test">>}, SetKeyspace).

rows_result_parse_test() ->
    Parser = parser(),
    Bin = <<131,0,0,195,8,0,0,1,160,0,0,0,2,0,0,0,1,0,0,0,
            11,0,4,116,101,115,116,0,3,116,97,98,0,8,102,
            105,114,115,116,95,105,100,0,2,0,9,115,101,99,
            111,110,100,95,105,100,0,13,0,8,99,111,108,95,
            98,111,111,108,0,4,0,10,99,111,108,95,100,111,
            117,98,108,101,0,7,0,9,99,111,108,95,102,108,
            111,97,116,0,8,0,8,99,111,108,95,105,110,101,
            116,0,16,0,7,99,111,108,95,105,110,116,0,9,0,8,
            99,111,108,95,108,105,115,116,0,32,0,13,0,7,99,
            111,108,95,109,97,112,0,33,0,13,0,13,0,8,99,111,
            108,95,116,101,120,116,0,13,0,6,99,111,108,95,
            116,115,0,11,0,0,0,2,0,0,0,8,0,0,0,0,0,0,0,3,0,
            0,0,4,104,97,104,97,255,255,255,255,255,255,255,
            255,255,255,255,255,255,255,255,255,255,255,255,
            255,255,255,255,255,255,255,255,255,0,0,0,4,104,
            97,104,97,255,255,255,255,0,0,0,8,0,0,0,0,0,0,0,
            1,0,0,0,5,115,101,99,105,100,0,0,0,1,1,0,0,0,8,
            64,9,30,184,81,235,133,31,0,0,0,4,63,157,112,
            164,0,0,0,4,127,0,0,1,0,0,0,4,0,0,0,10,0,0,0,27,
            0,0,0,3,0,0,0,3,111,110,101,0,0,0,3,116,119,111,
            0,0,0,5,116,104,114,101,101,0,0,0,74,0,0,0,4,0,
            0,0,3,107,101,121,0,0,0,5,118,97,117,108,101,0,
            0,0,4,107,101,121,49,0,0,0,6,118,97,108,117,101,
            49,0,0,0,4,107,101,121,50,0,0,0,6,118,97,108,
            117,101,50,0,0,0,4,107,101,121,51,0,0,0,6,118,
            97,108,117,101,50,0,0,0,4,116,101,120,116,0,0,0,
            8,0,0,0,0,0,0,77,111>>,

    Columns = [{<<"first_id">>,bigint}, {<<"second_id">>,varchar},
               {<<"col_bool">>,boolean}, {<<"col_double">>,double},
               {<<"col_float">>,float}, {<<"col_inet">>,inet},
               {<<"col_int">>,int}, {<<"col_list">>,{list,varchar}},
               {<<"col_map">>,{map,{varchar,varchar}}},
               {<<"col_text">>,varchar}, {<<"col_ts">>,timestamp}],

    {ok, #ecql_frame{stream = 195, opcode = ?OP_RESULT,
                     message = #ecql_result{kind = rows, data = Data}}, <<>>} = Parser(Bin),
    #ecql_rows{meta = Meta, data = [Row1|_] = Rows} = Data,
    ?assertEqual(Columns, Meta#ecql_rows_meta.columns),
    ?assertEqual([3,<<"haha">>,null,null,null,null,null,null, null,<<"haha">>,null], Row1).

parse_string_test() ->
    Str = <<"ok">>,
    ?assertEqual({Str, <<>>}, ecql_frame:parse_string(<<2:?short, Str/binary>>)).

parse_error_test() ->
    Error = ecql_frame:parse_error(#ecql_error{code = ?ERR_UNAVAILABE},
                                   <<1:?short, 10:?int, 20:?int>>),
    Detail = [{consistency, one}, {required, 10}, {alive, 20}],
    ?assertEqual(Detail, Error#ecql_error.detail).

string_list_test() ->
    List = [<<"abc">>, <<"defakd">>],
    ?assertEqual({List, <<>>}, ecql_frame:parse_string_list(
                                ecql_frame:serialize_string_list(List))).

%%string_multimap_test() ->
%%    MultiMap = [{<<"key">>, [<<"val1">>, <<"val2">>]},
%%                {<<"key2">>, [<<"val3">>, <<"val4">>]}],
%%    ?assertEqual({MultiMap, <<>>}, ecql_frame:parse_string_multimap(
%%                                    ecql_frame:serialize_string_multimap(MultiMap))).

serialize_query_test() ->
    Query = #ecql_query{query = <<"select * from tab">>,
                        consistency = ?CL_TWO,
                        values = [<<"a">>, <<"b">>],
                        skip_metadata = true,
                        result_page_size = 10,
                        paging_state = <<"akdkdakahdi2dk">>,
                        timestamp = 183820},
    ecql_frame:serialize_req(Query).

-endif.
