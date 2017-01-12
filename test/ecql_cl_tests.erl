%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015-2017 eMQTT.IO, All Rights Reserved.
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

-module(ecql_cl_tests).

-ifdef(TEST).

-include("ecql.hrl").

-include_lib("eunit/include/eunit.hrl").

-import(ecql_cl, [name/1, value/1]).

name_value_test() ->
    ?assertEqual(any,         name(value(any))),
    ?assertEqual(one,         name(value(one))),
    ?assertEqual(two,         name(value(two))),
    ?assertEqual(three,       name(value(three))),
    ?assertEqual(quorum,      name(value(quorum))),
    ?assertEqual(all,         name(value(all))),
    ?assertEqual(local_quorum,name(value(local_quorum))),
    ?assertEqual(each_quorum, name(value(each_quorum))),
    ?assertEqual(serial,      name(value(serial))),
    ?assertEqual(local_serial,name(value(local_serial))),
    ?assertEqual(local_one,   name(value(local_one))).

-endif.
