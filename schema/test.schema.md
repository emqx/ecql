## cqlsh

```
./cqlsh localhost -u cassandra -p cassandra
```

## Create User

```
CREATE USER test WITH PASSWORD 'public' SUPERUSER;
```

## Create Keyspace

```
CREATE KEYSPACE test WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

USE test;
```

## Create Table

```
CREATE TABLE test.tab(
    first_id bigint,
    second_id text,
    col_text text,
    col_int int,
    col_ts timestamp,
    col_bool boolean,
    col_float float,
    col_double double,
    col_inet  inet,
    col_list list<text>,
    col_map map<text, text>,
    PRIMARY KEY (first_id, second_id)
) WITH CLUSTERING ORDER BY (second_id DESC)

insert into test.tab(first_id, second_id, col_text, col_int, col_ts, col_bool, col_float, col_double, col_inet, col_list, col_map) values(1, 'secid', 'text', 10, 19823, true, 1.23, 3.14, '127.0.0.1', ['one', 'two', 'three'], {'key': 'value'});

update test.tab set col_map['key1'] = 'value1' where first_id = 1 and second_id = 'secid';
```

