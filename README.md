# Erlang Cassandra CQL Driver [![Build Status](https://travis-ci.org/emqtt/ecql.svg?branch=master)](https://travis-ci.org/emqtt/ecql)

Cassandra Native CQL Driver written in Erlang/OTP.

## Features

* CQL BINARY PROTOCOL v3 Support 
* Username, Password Authentication
* Query, Prepare and Execute

## Usage

### Schema

schema/test.schema.md

### Connect

Connect to localhost:9042:

```
{ok, C} = ecql:start_link().
```

Connect to nodes with username, password:

```
CassNodes = [{"localhost", 9042}, {"192.168.1.4", 9042}],
{ok, C} = ecql:start_link([{nodes, CassNodes}, {username, <<"test">>}, {password, <<"test">>}]).
```

### Query

```
{ok, KeySpace} = ecql:query(C, <<"use test">>).

{ok, {TableSpec, Columns, Rows}} = ecql:query(C, <<"select * from test.tab">>).

{ok, {TableSpec, Columns, Rows}} = ecql:query(C, <<"select * from test.tab where first_id = ? and second_id = ?">>, [{bigint, 1}, 'secid']).
```

### Prepare

```
{ok, Id} = ecql:prepare(C, <<"select * from test.tab where first_id = ? and second_id = ?">>).
```

### Execute

```
{ok, {TableSpec, Columns, Rows}} = ecql:execute(C, Id, [{bigint, 1}, 'secid']).
```

## Connect Options

```erlang
-type option() :: {nodes,    [{host(), inet:port_number()}]}
                | {username, binary()}
                | {password, binary()}
                | {tcp_opts, [gen_tcp:connect_option()]}
                | {ssl,      boolean()}
                | {ssl_opts, [ssl:ssl_option()]}
                | {timeout,  timeout()}
                | {logger,   atom() | {atom(), atom()}}.
```

## Logger

```erlang

%% log to stdout with info level
ecql:start_link([{logger, info}]).

%% log to otp standard error_logger with warning level
ecql:start_link([{logger, {otp, warning}}]).

%% log to lager with error level
ecql:start_link([{logger, {lager, error}}]).

```

### Logger modules

Module | Description
-------|------------
stdout | io:format
otp    | error_logger
lager  | lager

### Logger Levels

```
all
debug
info
warning
error
critical
none
```

## License

The MIT License (MIT)

## Author

Feng Lee <feng@emqtt.io>

