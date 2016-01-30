%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015-2016 Feng Lee <feng@emqtt.io>. All Rights Reserved.
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

%%------------------------------------------------------------------------------
%% 3. Notations
%%
%% [int]          A 4 bytes signed integer
%% [long]         A 8 bytes signed integer
%% [short]        A 2 bytes unsigned integer
%%------------------------------------------------------------------------------
-define(byte,   8/big-integer).
-define(short,  16/big-integer).
-define(int,    32/big-signed-integer).
-define(long,   64/big-signed-integer).
-define(float,  32/big-float).
-define(double, 64/big-float).
-define(uuid,   16/binary).

%%------------------------------------------------------------------------------
%% Cassandra Type
%%------------------------------------------------------------------------------

%% Custom: the value is a [string], see above.
-define(TYPE_CUSTOM,    16#00).
-define(TYPE_ASCII,     16#01).
-define(TYPE_BIGINT,    16#02).
-define(TYPE_BLOB,      16#03).
-define(TYPE_BOOLEAN,   16#04).
-define(TYPE_COUNTER,   16#05). 
-define(TYPE_DECIMAL,   16#06).
-define(TYPE_DOUBLE,    16#07).
-define(TYPE_FLOAT,     16#08).
-define(TYPE_INT,       16#09).
-define(TYPE_TIMESTAMP, 16#0B).
-define(TYPE_UUID,      16#0C).
-define(TYPE_VARCHAR,   16#0D).
-define(TYPE_VARINT,    16#0E).
-define(TYPE_TIMEUUID,  16#0F).
-define(TYPE_INET,      16#10).
%% the value is an [option], representing the type of the elements of the list.
-define(TYPE_LIST,      16#20).
%% the value is two [option], representing the types of the keys and values of the map
-define(TYPE_MAP,       16#21).
%% the value is an [option], representing the type of the elements of the set
-define(TYPE_SET,       16#22).
%% the value is <ks><udt_name><n><name_1><type_1>...<name_n><type_n>
-define(TYPE_UDT,       16#30).
-define(TYPE_TUPLE,     16#31).

