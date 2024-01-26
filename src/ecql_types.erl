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
%% @doc CQL Types.
%%
%% @author Feng Lee <feng@emqtt.io>
%%-----------------------------------------------------------------------------

-module(ecql_types).

-include("ecql_types.hrl").

-export([name/1, value/1, is_type/1, encode/1, encode/2,
         decode/2, decode/3, to_bytes/1, from_bytes/1]).

%%------------------------------------------------------------------------------
%% Type Name
%%------------------------------------------------------------------------------

name(?TYPE_CUSTOM)   -> custom;
name(?TYPE_ASCII)    -> ascii;
name(?TYPE_BIGINT)   -> bigint;
name(?TYPE_BLOB)     -> blob;
name(?TYPE_BOOLEAN)  -> boolean;
name(?TYPE_COUNTER)  -> counter;
name(?TYPE_DECIMAL)  -> decimal;
name(?TYPE_DOUBLE)   -> double;
name(?TYPE_FLOAT)    -> float;
name(?TYPE_INT)      -> int;
name(?TYPE_TIMESTAMP)-> timestamp;
name(?TYPE_UUID)     -> uuid;
name(?TYPE_VARCHAR)  -> varchar;
name(?TYPE_VARINT)   -> varint;
name(?TYPE_TIMEUUID) -> timeuuid;
name(?TYPE_INET)     -> inet;
name(?TYPE_LIST)     -> list;
name(?TYPE_MAP)      -> map;
name(?TYPE_SET)      -> set;
name(?TYPE_UDT)      -> udt;
name(?TYPE_TUPLE)    -> tuple.

value(custom)        -> ?TYPE_CUSTOM;
value(ascii)         -> ?TYPE_ASCII;
value(bigint)        -> ?TYPE_BIGINT;
value(blob)          -> ?TYPE_BLOB;
value(boolean)       -> ?TYPE_BOOLEAN;
value(counter)       -> ?TYPE_COUNTER;
value(decimal)       -> ?TYPE_DECIMAL;
value(double)        -> ?TYPE_DOUBLE;
value(float)         -> ?TYPE_FLOAT;
value(int)           -> ?TYPE_INT;
value(timestamp)     -> ?TYPE_TIMESTAMP;
value(uuid)          -> ?TYPE_UUID;
value(varchar)       -> ?TYPE_VARCHAR;
value(varint)        -> ?TYPE_VARINT;
value(timeuuid)      -> ?TYPE_TIMEUUID;
value(inet)          -> ?TYPE_INET;
value(list)          -> ?TYPE_LIST;
value(map)           -> ?TYPE_MAP;
value(set)           -> ?TYPE_SET;
value(udt)           -> ?TYPE_UDT;
value(tuple)         -> ?TYPE_TUPLE.

is_type(T) ->
    try value(T) of _I -> true catch error:_ -> false end.

%%------------------------------------------------------------------------------
%% Encode
%%------------------------------------------------------------------------------

encode(null) ->
    null;
encode(A) when is_atom(A) ->
    encode(text, atom_to_list(A));
encode(L) when is_list(L) ->
    encode(text, L);
encode(B) when is_binary(B) ->
    encode(text, B);
encode({Type, Val}) when is_atom(Type) ->
    encode(Type, Val).

encode(ascii, Bin) ->
    Bin;

encode(bigint, BigInt) ->
    <<BigInt:?long>>;

encode(blob, Bin) ->
    Bin;

encode(boolean, false) ->
    <<0>>;

encode(boolean, true) ->
    <<1>>;

encode(counter, Counter) ->
    <<Counter:?long>>;

encode(decimal, {Unscaled, Scale}) ->
    <<Scale:?int, (encode(varint, Unscaled))/binary>>;

encode(double, Double) ->
    <<Double:?double>>;

encode(float, Float) ->
    <<Float:?float>>;

encode(inet, {A, B, C, D}) ->
    <<A, B, C, D>>;

encode(inet, {A, B, C, D, E, F, G, H}) ->
    <<A:?short, B:?short, C:?short, D:?short,
      E:?short, F:?short, G:?short, H:?short>>;

encode(int, Int) ->
    <<Int:?int>>;

encode({list, ElType}, List) ->
    Encode = fun(El) -> to_bytes(encode(ElType, El)) end,
    ListBin = << <<(Encode(El))/binary>> || El <- List >>,
    <<(length(List)):?int, ListBin/binary>>;

encode({map, {KType, VType}}, Map) ->
    Encode = fun(Key, Val) ->
            KeyBin = to_bytes(encode(KType, Key)),
            ValBin = to_bytes(encode(VType, Val)),
            <<KeyBin/binary, ValBin/binary>>
    end,
    MapBin = << <<(Encode(Key, Val))/binary>> || {Key, Val} <- Map >>,
    <<(length(Map)):?int, MapBin/binary>>;

encode({set, ElType}, Set) ->
    encode({list, ElType}, ordsets:to_list(ordsets:from_list(Set)));

encode(text, Str) when is_list(Str) ->
    list_to_binary(Str);
encode(text, Bin) ->
    Bin;

encode(timestamp, TS) ->
    <<TS:?long>>;

encode(uuid, UUID) ->
    <<UUID:16/binary>>;

encode(varchar, Str) when is_list(Str) ->
    list_to_binary(Str);
encode(varchar, Bin) ->
    Bin;

encode(varint, Varint) when 16#80 > Varint andalso Varint >= -16#80 ->
    <<Varint:1/big-signed-unit:8>>;

encode(varint, Varint) ->
    <<Varint:2/big-signed-unit:8>>;

encode(timeuuid, UUID) ->
    <<UUID:16/binary>>;

encode({tuple, Types}, Tuple) ->
    L = lists:zip(tuple_to_list(Types), tuple_to_list(Tuple)),
    Encode = fun(Type, El) -> to_bytes(encode(Type, El)) end,
    << <<(Encode(Type, El))/binary>> || {Type, El} <- L >>.

to_bytes(null) ->
    <<-1:32/big-signed-integer>>;
to_bytes(Bin) ->
    <<(size(Bin)):?int, Bin/binary>>.

%%------------------------------------------------------------------------------
%% Decode
%%------------------------------------------------------------------------------
decode(Type, Bin) ->
    decode(Type, size(Bin), Bin).

decode(ascii, Size, Bin) ->
    <<Ascii:Size/binary, Rest/binary>> = Bin, {Ascii, Rest};

decode(bigint, 8, <<Bigint:?long, Rest/binary>>) ->
    {Bigint, Rest};

decode(blob, Size, Bin) ->
    <<Blob:Size/binary, Rest/binary>> = Bin, {Blob, Rest};

decode(boolean, 1, <<0, Rest/binary>>) ->
    {false, Rest};

decode(boolean, 1, <<_, Rest/binary>>) ->
    {true, Rest};

decode(counter, 8, <<Counter:?long, Rest/binary>>) ->
    {Counter, Rest};

decode(decimal, Size, <<Scale:?int, Bin/binary>>) ->
    {Unscaled, Rest} = decode(varint, Size - 4, Bin),
    {{Unscaled, Scale}, Rest};

decode(double, 8, <<Double:?double, Rest/binary>>) ->
    {Double, Rest};

decode(float, 4, <<Float:?float, Rest/binary>>) ->
    {Float, Rest};

decode(inet, 4, <<A, B, C, D, Rest/binary>>) ->
    {{A, B, C, D}, Rest};

decode(inet, 16, <<A:?short, B:?short, C:?short, D:?short,
                   E:?short, F:?short, G:?short, H:?short, Rest/binary>>) ->
    {{A, B, C, D, E, F, G, H}, Rest};

decode(int, 4, Bin) ->
    <<Int:?int, Rest/binary>> = Bin, {Int, Rest};

decode({list, ElType}, Size, Bin) ->
    <<ListBin:Size/binary, Rest/binary>> = Bin, <<_Len:?int, ElsBin/binary>> = ListBin,
    {[element(1, decode(ElType, ElSize, ElBin))
        || <<ElSize:?int, ElBin:ElSize/binary>> <= ElsBin], Rest};

decode({map, {KeyType, ValType}}, Size, Bin) ->
    <<MapBin:Size/binary, Rest/binary>> = Bin, <<_Len:?int, ElsBin/binary>> = MapBin,
    List = [ {decode(KeyType, KeySize, KeyBin), decode(ValType, ValSize, ValBin)}
            || << KeySize:?int, KeyBin:KeySize/binary, ValSize:?int, ValBin:ValSize/binary >> <= ElsBin ],
    {[{Key, Val} || {{Key, _}, {Val, _}} <- List], Rest};

decode({set,  ElType}, Size, Bin) ->
    {List, Rest} = decode({list, ElType}, Size, Bin),
    {ordsets:to_list(ordsets:from_list(List)), Rest};

decode(text, Size, Bin) ->
    <<Text:Size/binary, Rest/binary>> = Bin, {Text, Rest};

decode(timestamp, 8, <<TS:?long, Rest/binary>>) ->
    {TS, Rest};

decode(uuid, 16, <<UUID:16/binary, Rest/binary>>) ->
    {UUID, Rest};

decode(varchar, Size, Bin) ->
    <<Varchar:Size/binary, Rest/binary>> = Bin, {Varchar, Rest};

decode(varint, 1, <<Varint:1/big-signed-unit:8, Rest/binary>>) ->
    {Varint, Rest};

decode(varint, 2, <<Varint:2/big-signed-unit:8, Rest/binary>>) ->
    {Varint, Rest};

decode(timeuuid, 16, <<UUID:16/binary, Rest/binary>>) ->
    {UUID, Rest};

decode({tuple, ElTypes}, Size, Bin) ->
    <<TupleBin:Size/binary, Rest/binary>> = Bin,
    Elements = [{ElSize, ElBin} || <<ElSize:?int, ElBin:ElSize/binary>> <= TupleBin],
    List = [decode(ElType, ElSize, ElBin) || {ElType, {ElSize, ElBin}}
                                             <- lists:zip(tuple_to_list(ElTypes), Elements)],
    {list_to_tuple([El || {El, _} <- List]), Rest}.

from_bytes(<<Size:?int, Bin:Size/binary, Rest/binary>>) ->
    {Bin, Rest}.
