# ecql

Erlang Cassandra CQL Driver


## Prepare

```
{ok, Id} = ecql:prepare(C, <<"select * from emqchat.messages where message_to = ?">>),
ecql:execute(C, Id, [<<"feng">>], one).
```

