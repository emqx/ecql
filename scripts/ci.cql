-- create the table required by the ecql_tests.erl
CREATE TABLE test.tab (first_id bigint, second_id text, col_text text, col_map map<text, text>, PRIMARY KEY (first_id, second_id));

