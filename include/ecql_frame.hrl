
%% Type

-define(byte, 8).
-define(short,1/big-signed-unit:16).
-define(int,  1/big-signed-unit:32).
-define(long, 1/big-signed-unit:64).
-define(uuid, 16/binary).


%%------------------------------------------------------------------------------
%% Column Type
%%------------------------------------------------------------------------------

%% Custom: the value is a [string], see above.
-define(TYPE_CUSTOM,    16#0000).
-define(TYPE_ASCII,     16#0001).
-define(TYPE_BIGINT,    16#0002).
-define(TYPE_BLOB,      16#0003).
-define(TYPE_BOOLEAN,   16#0004).
-define(TYPE_COUNTER,   16#0005). 
-define(TYPE_DECIMAL,   16#0006).
-define(TYPE_DOUBLE,    16#0007).
-define(TYPE_FLOAT,     16#0008).
-define(TYPE_INT,       16#0009).
-define(TYPE_TIMESTAMP, 16#000B).
-define(TYPE_UUID,      16#000C).
-define(TYPE_VARCHAR,   16#000D).
-define(TYPE_VARINT,    16#000E).
-define(TYPE_TIMEUUID,  16#000F).
-define(TYPE_INET,      16#0010).
%% the value is an [option], representing the type of the elements of the list.
-define(TYPE_LIST,      16#0020).
%% the value is two [option], representing the types of the keys and values of the map
-define(TYPE_MAP,       16#0021).
%% the value is an [option], representing the type of the elements of the set
-define(TYPE_SET,       16#0022).
%% the value is <ks><udt_name><n><name_1><type_1>...<name_n><type_n>
-define(TYPE_UDT,       16#0030).
-define(TYPE_TUPLE,     16#0031).

