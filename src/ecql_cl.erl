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
%%% @doc CQL Consistency Level.
%%%
%%% @author Feng Lee <feng@emqtt.io>
%%%-----------------------------------------------------------------------------

-module(ecql_cl).

-include("ecql.hrl").

-export([name/1, value/1]).

value(any)          -> ?CL_ANY;
value(one)          -> ?CL_ONE;
value(two)          -> ?CL_TWO;
value(three)        -> ?CL_THREE;
value(quorum)       -> ?CL_QUORUM;
value(all)          -> ?CL_ALL;
value(local_quorum) -> ?CL_LOCAL_QUORUM;
value(each_quorum)  -> ?CL_EACH_QUORUM;
value(serial)       -> ?CL_SERIAL;
value(local_serial) -> ?CL_LOCAL_SERIAL;
value(local_one)    -> ?CL_LOCAL_ONE.

name(?CL_ANY)          -> any;
name(?CL_ONE)          -> one;
name(?CL_TWO)          -> two;
name(?CL_THREE)        -> three;
name(?CL_QUORUM)       -> quorum;
name(?CL_ALL)          -> all;
name(?CL_LOCAL_QUORUM) -> local_quorum;
name(?CL_EACH_QUORUM)  -> each_quorum;
name(?CL_SERIAL)       -> serial;
name(?CL_LOCAL_SERIAL) -> local_serial;
name(?CL_LOCAL_ONE)    -> local_one.

