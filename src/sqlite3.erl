%%%-------------------------------------------------------------------
%%% File    : sqlite3.erl
%%% @author Tee Teoh
%%% @copyright 21 Jun 2008 by Tee Teoh
%%% @version 1.0.0
%%% @doc Library module for sqlite3
%%% @end
%%%-------------------------------------------------------------------
-module(sqlite3).
-include("sqlite3.hrl").
-export_types([sql_value/0, sql_type/0, table_info/0, sqlite_error/0, 
               sql_params/0, sql_non_query_result/0, sql_result/0]).

-behaviour(gen_server).

%% API
-export([open/1, open/2]).
-export([start_link/1, start_link/2]).
-export([stop/0, close/1, close_timeout/2]).
-export([sql_exec/1, sql_exec/2, sql_exec_timeout/3, 
         sql_exec_script/2, sql_exec_script_timeout/3, 
         sql_exec/3, sql_exec_timeout/4]).
-export([prepare/2, bind/3, next/2, reset/2, clear_bindings/2, finalize/2,
         columns/2, prepare_timeout/3, bind_timeout/4, next_timeout/3,
         reset_timeout/3, clear_bindings_timeout/3, finalize_timeout/3,
         columns_timeout/3]).
-export([create_table/2, create_table/3, create_table/4, create_table_timeout/4,
         create_table_timeout/5]).
-export([list_tables/0, list_tables/1, list_tables_timeout/2, 
         table_info/1, table_info/2, table_info_timeout/3]).
-export([write/2, write/3, write_timeout/4, write_many/2, write_many/3,
         write_many_timeout/4]).
-export([update/3, update/4, update_timeout/5]).
-export([read_all/2, read_all/3, read_all_timeout/3, read_all_timeout/4, 
         read/2, read/3, read/4, read_timeout/4, read_timeout/5]).
-export([delete/2, delete/3, delete_timeout/4]).
-export([drop_table/1, drop_table/2, drop_table_timeout/3]).
-export([vacuum/0, vacuum/1, vacuum_timeout/2]).

%% -export([create_function/3]).

-export([value_to_sql/1, value_to_sql_unsafe/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define('DRIVER_NAME', 'sqlite3_drv').
-record(state, {port, ops = [], refs = dict:new()}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% @spec start_link(Db :: atom()) -> {ok, Pid :: pid()} | ignore | {error, Error}
%% @doc 
%%   Opens the sqlite3 database in file Db.db in the working directory 
%%   (creating this file if necessary). This is the same as open/1.
%% @end
%%--------------------------------------------------------------------
-type option() :: {file, string()} | temporary | in_memory.
-type result() :: {'ok', pid()} | 'ignore' | {'error', any()}.

-spec start_link(atom()) -> result().
start_link(Db) ->
    open(Db, []).

%%--------------------------------------------------------------------
%% @spec start_link(Db :: atom(), Options) -> {ok, Pid :: pid()} | ignore | {error, Error}
%% @doc 
%%   Opens a sqlite3 database creating one if necessary. By default the 
%%   database will be called Db.db in the current path. This can be changed 
%%   by passing the option {file, DbFile :: String()}. DbFile must be the 
%%   full path to the sqlite3 db file. start_link/1 can be use with stop/0, 
%%   sql_exec/1, create_table/2, list_tables/0, table_info/1, write/2, 
%%   read/2, delete/2 and drop_table/1. This is the same as open/2.
%% @end
%%--------------------------------------------------------------------
-spec start_link(atom(), [option()]) -> result().
start_link(Db, Options) ->
    open(Db, Options).

%%--------------------------------------------------------------------
%% @spec open(Db :: atom()) -> {ok, Pid :: pid()} | ignore | {error, Error}
%% @doc
%%   Opens the sqlite3 database in file Db.db in the working directory 
%%   (creating this file if necessary). This is the same as open/1.
%% @end
%%--------------------------------------------------------------------
-spec open(atom()) -> result().
open(Db) ->
    open(Db, []).

%%--------------------------------------------------------------------
%% @spec open(Db :: atom(), Options :: [option()]) -> {ok, Pid :: pid()} | ignore | {error, Error}
%% @type option() = {file, DbFile :: string()} | in_memory | temporary
%%   
%% @doc
%%   Opens a sqlite3 database creating one if necessary. By default the database
%%   will be called Db.db in the current path. This can be changed by
%%   passing the option {file, DbFile :: string()}. DbFile must be the full
%%   path to the sqlite3 db file. Can be use to open multiple sqlite3 databases
%%   per node. Must be use in conjunction with stop/1, sql_exec/2,
%%   create_table/3, list_tables/1, table_info/2, write/3, read/3, delete/3
%%   and drop_table/2.
%% @end
%%--------------------------------------------------------------------
-spec open(atom(), [option()]) -> result().
open(Db, Options) ->
    Opts = case proplists:lookup(file, Options) of
               none ->
                   DbName = case proplists:is_defined(temporary, Options) of
                                true -> 
                                    "";
                                false ->
                                    case proplists:is_defined(in_memory, Options) of
                                        true -> 
                                            ":memory:";
                                        false ->
                                            "./" ++ atom_to_list(Db) ++ ".db"
                                    end
                            end,
                   [{file, DbName} | Options];
               {file, _} -> 
                   Options
           end,
    gen_server:start_link({local, Db}, ?MODULE, Opts, []).

%%--------------------------------------------------------------------
%% @spec close(Db :: atom()) -> ok
%% @doc
%%   Closes the Db sqlite3 database.
%% @end
%%--------------------------------------------------------------------
-spec close(atom()) -> 'ok'.
close(Db) ->
    gen_server:call(Db, close).

%%--------------------------------------------------------------------
%% @spec close_timeout(Db :: atom(), Timeout :: timeout()) -> ok
%% @doc
%%   Closes the Db sqlite3 database.
%% @end
%%--------------------------------------------------------------------
-spec close_timeout(atom(), timeout()) -> 'ok'.
close_timeout(Db, Timeout) ->
    gen_server:call(Db, close, Timeout).

%%--------------------------------------------------------------------
%% @spec stop() -> ok
%% @doc
%%   Closes the sqlite3 database.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> 'ok'.
stop() ->
    close(?MODULE).

%%--------------------------------------------------------------------
%% @spec sql_exec(Sql :: iodata()) -> sql_result()
%% @doc
%%   Executes the Sql statement directly.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec(iodata()) -> sql_result().
sql_exec(SQL) ->
    sql_exec(?MODULE, SQL).

%%--------------------------------------------------------------------
%% @spec sql_exec(Db :: atom(), Sql :: iodata()) -> sql_result()
%% @doc
%%   Executes the Sql statement directly on the Db database. Returns the
%%   result of the Sql call.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec(atom(), iodata()) -> sql_result().
sql_exec(Db, SQL) ->
    gen_server:call(Db, {sql_exec, SQL}).

%%--------------------------------------------------------------------
%% @spec sql_exec(Db :: atom(), Sql :: iodata(), Params) -> sql_result()
%%   Params = [sql_value() | {atom() | string() | integer(), sql_value()}]
%% @doc
%%   Executes the Sql statement with parameters Params directly on the Db 
%%   database. Returns the result of the Sql call.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec(atom(), iodata(), [sql_value() | {atom() | string() | integer(), sql_value()}]) -> 
       sql_result().
sql_exec(Db, SQL, Params) ->
    gen_server:call(Db, {sql_bind_and_exec, SQL, Params}).

%%--------------------------------------------------------------------
%% @spec sql_exec_timeout(Db :: atom(), Sql :: iodata(), Timeout :: timeout()) -> sql_result()
%% @doc
%%   Executes the Sql statement directly on the Db database. Returns the
%%   result of the Sql call.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec_timeout(atom(), iodata(), timeout()) -> sql_result().
sql_exec_timeout(Db, SQL, Timeout) ->
    gen_server:call(Db, {sql_exec, SQL}, Timeout).

%%--------------------------------------------------------------------
%% @spec sql_exec_timeout(Db :: atom(), Sql :: iodata(), Params, Timeout :: timeout()) -> sql_result()
%%   Params = [sql_value() | {atom() | string() | integer(), sql_value()}]
%% @doc
%%   Executes the Sql statement with parameters Params directly on the Db 
%%   database. Returns the result of the Sql call.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec_timeout(atom(), iodata(), [sql_value() | {atom() | string() | integer(), sql_value()}], timeout()) -> 
       sql_result().
sql_exec_timeout(Db, SQL, Params, Timeout) ->
    gen_server:call(Db, {sql_bind_and_exec, SQL, Params}, Timeout).

%%--------------------------------------------------------------------
%% @spec sql_exec_script(Db :: atom(), Sql :: iodata()) -> [sql_result()]
%% @doc
%%   Executes the Sql script (consisting of semicolon-separated statements) 
%%   directly on the Db database. Returns the list of their results (same as
%%   if sql_exec/2 was called for all of them in order, but more efficient). 
%%   Note that any whitespace or comments after the last semicolon will be 
%%   considered an empty statement and produce the corresponding error.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec_script(atom(), iodata()) -> [sql_result()].
sql_exec_script(Db, SQL) ->
    gen_server:call(Db, {sql_exec_script, SQL}).

%%--------------------------------------------------------------------
%% @spec sql_exec_script_timeout(Db :: atom(), Sql :: iodata(), Timeout :: timeout()) -> [sql_result()]
%% @doc
%%   Executes the Sql script (consisting of semicolon-separated statements) 
%%   directly on the Db database. Returns the list of their results (same as
%%   if sql_exec/3 was called for all of them in order, but more efficient). 
%%   Note that any whitespace or comments after the last semicolon will be 
%%   considered an empty statement and produce the corresponding error.
%% @end
%%--------------------------------------------------------------------
-spec sql_exec_script_timeout(atom(), iodata(), timeout()) -> [sql_result()].
sql_exec_script_timeout(Db, SQL, Timeout) ->
    gen_server:call(Db, {sql_exec_script, SQL}, Timeout).

-spec prepare(atom(), iodata()) -> {ok, reference()} | sqlite_error().
prepare(Db, SQL) ->
    gen_server:call(Db, {prepare, SQL}).

-spec bind(atom(), reference(), sql_params()) -> sql_non_query_result().
bind(Db, Ref, Params) ->
    gen_server:call(Db, {bind, Ref, Params}).

-spec next(atom(), reference()) -> tuple() | done | sqlite_error().
next(Db, Ref) ->
    gen_server:call(Db, {next, Ref}).

-spec reset(atom(), reference()) -> sql_non_query_result().
reset(Db, Ref) ->
    gen_server:call(Db, {reset, Ref}).

-spec clear_bindings(atom(), reference()) -> sql_non_query_result().
clear_bindings(Db, Ref) ->
    gen_server:call(Db, {clear_bindings, Ref}).

-spec finalize(atom(), reference()) -> sql_non_query_result().
finalize(Db, Ref) ->
    gen_server:call(Db, {finalize, Ref}).

-spec columns(atom(), reference()) -> sql_non_query_result().
columns(Db, Ref) ->
    gen_server:call(Db, {columns, Ref}).

-spec prepare_timeout(atom(), iodata(), timeout()) -> {ok, reference()} | sqlite_error().
prepare_timeout(Db, SQL, Timeout) ->
    gen_server:call(Db, {prepare, SQL}, Timeout).

-spec bind_timeout(atom(), reference(), sql_params(), timeout()) -> sql_non_query_result().
bind_timeout(Db, Ref, Params, Timeout) ->
    gen_server:call(Db, {bind, Ref, Params}, Timeout).

-spec next_timeout(atom(), reference(), timeout()) -> tuple() | done | sqlite_error().
next_timeout(Db, Ref, Timeout) ->
    gen_server:call(Db, {next, Ref}, Timeout).

-spec reset_timeout(atom(), reference(), timeout()) -> sql_non_query_result().
reset_timeout(Db, Ref, Timeout) ->
    gen_server:call(Db, {reset, Ref}, Timeout).

-spec clear_bindings_timeout(atom(), reference(), timeout()) -> sql_non_query_result().
clear_bindings_timeout(Db, Ref, Timeout) ->
    gen_server:call(Db, {clear_bindings, Ref}, Timeout).

-spec finalize_timeout(atom(), reference(), timeout()) -> sql_non_query_result().
finalize_timeout(Db, Ref, Timeout) ->
    gen_server:call(Db, {finalize, Ref}, Timeout).

-spec columns_timeout(atom(), reference(), timeout()) -> sql_non_query_result().
columns_timeout(Db, Ref, Timeout) ->
    gen_server:call(Db, {columns, Ref}, Timeout).

%%--------------------------------------------------------------------
%% @spec create_table(Tbl :: atom(), TblInfo :: table_info()) -> sql_non_query_result()
%% @doc
%%   Creates the Tbl table using TblInfo as the table structure. The
%%   table structure is a list of {column name, column type} pairs.
%%   e.g. [{name, text}, {age, integer}]
%%
%%   Returns the result of the create table call.
%% @end
%%--------------------------------------------------------------------
-spec create_table(atom(), table_info()) -> sql_non_query_result().
create_table(Tbl, Columns) ->
    create_table(?MODULE, Tbl, Columns).

%%--------------------------------------------------------------------
%% @spec create_table(Db :: atom(), Tbl :: atom(), Columns) -> sql_non_query_result()
%%     Columns = table_info()
%% @doc
%%   Creates the Tbl table in Db using Columns as the table structure. 
%%   The table structure is a list of {column name, column type} pairs. 
%%   e.g. [{name, text}, {age, integer}]
%%
%%   Returns the result of the create table call.
%% @end
%%--------------------------------------------------------------------
-spec create_table(atom(), atom(), table_info()) -> sql_non_query_result().
create_table(Db, Tbl, Columns) ->
    gen_server:call(Db, {create_table, Tbl, Columns}).

%%--------------------------------------------------------------------
%% @spec create_table_timeout(Db :: atom(), Tbl :: atom(), Columns, Timeout :: timeout()) -> sql_non_query_result()
%%     Columns = table_info()
%% @doc
%%   Creates the Tbl table in Db using Columns as the table structure. 
%%   The table structure is a list of {column name, column type} pairs. 
%%   e.g. [{name, text}, {age, integer}]
%%
%%   Returns the result of the create table call.
%% @end
%%--------------------------------------------------------------------
-spec create_table_timeout(atom(), atom(), table_info(), timeout()) -> sql_non_query_result().
create_table_timeout(Db, Tbl, Columns, Timeout) ->
    gen_server:call(Db, {create_table, Tbl, Columns}, Timeout).

%%--------------------------------------------------------------------
%% @spec create_table(Db :: atom(), Tbl :: atom(), TblInfo, Constraints) -> sql_non_query_result()
%%     Columns = table_info()
%%     Constraints = [term()]
%% @doc
%%   Creates the Tbl table in Db using Columns as the table structure and
%%   Constraints as table constraints. 
%%   The table structure is a list of {column name, column type} pairs. 
%%   e.g. [{name, text}, {age, integer}]
%%
%%   Returns the result of the create table call.
%% @end
%%--------------------------------------------------------------------
-spec create_table(atom(), atom(), table_info(), table_constraints()) -> 
          sql_non_query_result().
create_table(Db, Tbl, Columns, Constraints) ->
    gen_server:call(Db, {create_table, Tbl, Columns, Constraints}).

%%--------------------------------------------------------------------
%% @spec create_table_timeout(Db :: atom(), Tbl :: atom(), TblInfo, Constraints, Timeout) -> sql_non_query_result()
%%     Columns = table_info()
%%     Constraints = [term()]
%% @doc
%%   Creates the Tbl table in Db using Columns as the table structure and
%%   Constraints as table constraints. 
%%   The table structure is a list of {column name, column type} pairs. 
%%   e.g. [{name, text}, {age, integer}]
%%
%%   Returns the result of the create table call.
%% @end
%%--------------------------------------------------------------------
-spec create_table_timeout(atom(), atom(), table_info(), table_constraints(), timeout()) -> 
          sql_non_query_result().
create_table_timeout(Db, Tbl, Columns, Constraints, Timeout) ->
    gen_server:call(Db, {create_table, Tbl, Columns, Constraints}, Timeout).

%%--------------------------------------------------------------------
%% @spec list_tables() -> [atom()]
%% @doc
%%   Returns a list of tables.
%% @end
%%--------------------------------------------------------------------
-spec list_tables() -> [atom()].
list_tables() ->
    list_tables(?MODULE).

%%--------------------------------------------------------------------
%% @spec list_tables(Db :: atom()) -> [atom()]
%% @doc
%%   Returns a list of tables for Db.
%% @end
%%--------------------------------------------------------------------
-spec list_tables(atom()) -> [atom()].
list_tables(Db) ->
    gen_server:call(Db, list_tables).

%%--------------------------------------------------------------------
%% @spec list_tables_timeout(Db :: atom(), Timeout :: timeout()) -> [atom()]
%% @doc
%%   Returns a list of tables for Db.
%% @end
%%--------------------------------------------------------------------
-spec list_tables_timeout(atom(), timeout()) -> [atom()].
list_tables_timeout(Db, Timeout) ->
    gen_server:call(Db, list_tables, Timeout).

%%--------------------------------------------------------------------
%% @spec table_info(Tbl :: atom()) -> table_info()
%% @doc
%%    Returns table schema for Tbl.
%% @end
%%--------------------------------------------------------------------
-spec table_info(atom()) -> table_info().
table_info(Tbl) ->
    table_info(?MODULE, Tbl).

%%--------------------------------------------------------------------
%% @spec table_info(Db :: atom(), Tbl :: atom()) -> table_info()
%% @doc
%%   Returns table schema for Tbl in Db.
%% @end
%%--------------------------------------------------------------------
-spec table_info(atom(), atom()) -> table_info().
table_info(Db, Tbl) ->
    gen_server:call(Db, {table_info, Tbl}).

%%--------------------------------------------------------------------
%% @spec table_info_timeout(Db :: atom(), Tbl :: atom(), Timeout :: timeout()) -> table_info()
%% @doc
%%   Returns table schema for Tbl in Db.
%% @end
%%--------------------------------------------------------------------
-spec table_info_timeout(atom(), atom(), timeout()) -> table_info().
table_info_timeout(Db, Tbl, Timeout) ->
    gen_server:call(Db, {table_info, Tbl}, Timeout).

%%--------------------------------------------------------------------
%% @spec write(Tbl :: atom(), Data) -> sql_non_query_result()
%%         Data = [{Column :: atom(), Value :: sql_value()}]
%% @doc
%%   Write Data into Tbl table. Value must be of the same type as 
%%   determined from table_info/2.
%% @end
%%--------------------------------------------------------------------
-spec write(atom(), [{atom(), sql_value()}]) -> sql_non_query_result().
write(Tbl, Data) ->
    write(?MODULE, Tbl, Data).

%%--------------------------------------------------------------------
%% @spec write(Db :: atom(), Tbl :: atom(), Data) -> sql_non_query_result()
%%         Data = [{Column :: atom(), Value :: sql_value()}]
%% @doc
%%   Write Data into Tbl table in Db database. Value must be of the 
%%   same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec write(atom(), atom(), [{atom(), sql_value()}]) -> sql_non_query_result().
write(Db, Tbl, Data) ->
    gen_server:call(Db, {write, Tbl, Data}).

%%--------------------------------------------------------------------
%% @spec write_timeout(Db :: atom(), Tbl :: atom(), Data, Timeout :: timeout()) -> sql_non_query_result()
%%         Data = [{Column :: atom(), Value :: sql_value()}]
%% @doc
%%   Write Data into Tbl table in Db database. Value must be of the 
%%   same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec write_timeout(atom(), atom(), [{atom(), sql_value()}], timeout()) -> sql_non_query_result().
write_timeout(Db, Tbl, Data, Timeout) ->
    gen_server:call(Db, {write, Tbl, Data}, Timeout).

%%--------------------------------------------------------------------
%% @spec write_many(Tbl :: atom(), Data) -> sql_non_query_result()
%%         Data = [[{Column :: atom(), Value :: sql_value()}]]
%% @doc
%%   Write all records in Data into table Tbl. Value must be of the 
%%   same type as determined from table_info/2.
%% @end
%%--------------------------------------------------------------------
-spec write_many(atom(), [[{atom(), sql_value()}]]) -> sql_non_query_result().
write_many(Tbl, Data) ->
    write_many(?MODULE, Tbl, Data).

%%--------------------------------------------------------------------
%% @spec write_many(Db :: atom(), Tbl :: atom(), Data) -> sql_non_query_result()
%%         Data = [[{Column :: atom(), Value :: sql_value()}]]
%% @doc
%%   Write all records in Data into table Tbl in database Db. Value 
%%   must be of the same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec write_many(atom(), atom(), [[{atom(), sql_value()}]]) -> sql_non_query_result().
write_many(Db, Tbl, Data) ->
    gen_server:call(Db, {write_many, Tbl, Data}).

%%--------------------------------------------------------------------
%% @spec write_many_timeout(Db :: atom(), Tbl :: atom(), Data, Timeout :: timeout()) -> sql_non_query_result()
%%         Data = [[{Column :: atom(), Value :: sql_value()}]]
%% @doc
%%   Write all records in Data into table Tbl in database Db. Value 
%%   must be of the same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec write_many_timeout(atom(), atom(), [[{atom(), sql_value()}]], timeout()) -> sql_non_query_result().
write_many_timeout(Db, Tbl, Data, Timeout) ->
    gen_server:call(Db, {write_many, Tbl, Data}, Timeout).

%%--------------------------------------------------------------------
%% @spec update(Tbl :: atom(), {Key :: atom(), Value}, Data) -> sql_non_query_result()
%%        Value = any()
%%        Data = [{Column :: atom(), Value :: sql_value()}]
%% @doc
%%    Updates rows into Tbl table such that the Value matches the
%%    value in Key with Data.
%% @end
%%--------------------------------------------------------------------
-spec update(atom(), {atom(), sql_value()}, [{atom(), sql_value()}]) -> sql_non_query_result().
update(Tbl, {Key, Value}, Data) ->
    update(?MODULE, Tbl, {Key, Value}, Data).

%%--------------------------------------------------------------------
%% @spec update(Db :: atom(), Tbl :: atom(), {Key :: atom(), Value}, Data) -> sql_non_query_result()
%%        Value = sql_value()
%%        Data = [{Column :: atom(), Value :: sql_value()}]
%% @doc
%%    Updates rows into Tbl table in Db database such that the Value
%%    matches the value in Key with Data.
%% @end
%%--------------------------------------------------------------------
-spec update(atom(), atom(), {atom(), sql_value()}, [{atom(), sql_value()}]) -> 
          sql_non_query_result().
update(Db, Tbl, {Key, Value}, Data) ->
  gen_server:call(Db, {update, Tbl, Key, Value, Data}).

%%--------------------------------------------------------------------
%% @spec update_timeout(Db :: atom(), Tbl :: atom(), {Key :: atom(), Value}, Data, Timeout :: timeout()) -> sql_non_query_result()
%%        Value = sql_value()
%%        Data = [{Column :: atom(), Value :: sql_value()}]
%% @doc
%%    Updates rows into Tbl table in Db database such that the Value
%%    matches the value in Key with Data.
%% @end
%%--------------------------------------------------------------------
-spec update_timeout(atom(), atom(), {atom(), sql_value()}, [{atom(), sql_value()}], timeout()) -> 
          sql_non_query_result().
update_timeout(Db, Tbl, {Key, Value}, Data, Timeout) ->
  gen_server:call(Db, {update, Tbl, Key, Value, Data}, Timeout).

%%--------------------------------------------------------------------
%% @spec read_all(Db :: atom(), Table :: atom()) -> sql_result()
%% @doc
%%   Reads all rows from Table in Db.
%% @end
%%--------------------------------------------------------------------
-spec read_all(atom(), atom()) -> sql_result().
read_all(Db, Tbl) ->
    gen_server:call(Db, {read, Tbl}).

%%--------------------------------------------------------------------
%% @spec read_all_timeout(Db :: atom(), Table :: atom(), Timeout :: timeout()) -> sql_result()
%% @doc
%%   Reads all rows from Table in Db.
%% @end
%%--------------------------------------------------------------------
-spec read_all_timeout(atom(), atom(), timeout()) -> sql_result().
read_all_timeout(Db, Tbl, Timeout) ->
    gen_server:call(Db, {read, Tbl}, Timeout).

%%--------------------------------------------------------------------
%% @spec read_all(Db :: atom(), Table :: atom(), Columns :: [atom()]) -> sql_result()
%% @doc
%%   Reads Columns in all rows from Table in Db.
%% @end
%%--------------------------------------------------------------------
-spec read_all(atom(), atom(), [atom()]) -> sql_result().
read_all(Db, Tbl, Columns) ->
    gen_server:call(Db, {read, Tbl, Columns}).

%%--------------------------------------------------------------------
%% @spec read_all_timeout(Db :: atom(), Table :: atom(), Columns :: [atom()], Timeout :: timeout()) -> sql_result()
%% @doc
%%   Reads Columns in all rows from Table in Db.
%% @end
%%--------------------------------------------------------------------
-spec read_all_timeout(atom(), atom(), [atom()], timeout()) -> sql_result().
read_all_timeout(Db, Tbl, Columns, Timeout) ->
    gen_server:call(Db, {read, Tbl, Columns}, Timeout).

%%--------------------------------------------------------------------
%% @spec read(Tbl :: atom(), Key) -> sql_result()
%%         Key = {Column :: atom(), Value :: sql_value()}
%% @doc
%%   Reads a row from Tbl table such that the Value matches the 
%%   value in Column. Value must have the same type as determined 
%%   from table_info/2.
%% @end
%%--------------------------------------------------------------------
-spec read(atom(), {atom(), sql_value()}) -> sql_result().
read(Tbl, Key) ->
    read(?MODULE, Tbl, Key).

%%--------------------------------------------------------------------
%% @spec read(Db :: atom(), Tbl :: atom(), Key) -> sql_result()
%%         Key = {Column :: atom(), Value :: sql_value()}
%% @doc
%%   Reads a row from Tbl table in Db database such that the Value 
%%   matches the value in Column. ColValue must have the same type 
%%   as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec read(atom(), atom(), {atom(), sql_value()}) -> sql_result().
read(Db, Tbl, {Column, Value}) ->
    gen_server:call(Db, {read, Tbl, Column, Value}).

%%--------------------------------------------------------------------
%% @spec read(Db, Tbl, Key, Columns) -> [any()]
%%        Db = atom()
%%        Tbl = atom()
%%        Key = {Column :: atom(), Value :: sql_value()}
%%        Columns = [atom()]
%% @doc
%%    Reads a row from Tbl table in Db database such that the Value
%%    matches the value in Column. Value must have the same type as 
%%    determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec read(atom(), atom(), {atom(), sql_value()}, [atom()]) -> sql_result().
read(Db, Tbl, {Key, Value}, Columns) ->
    gen_server:call(Db, {read, Tbl, Key, Value, Columns}).

%%--------------------------------------------------------------------
%% @spec read_timeout(Db :: atom(), Tbl :: atom(), Key, Timeout :: timeout()) -> sql_result()
%%         Key = {Column :: atom(), Value :: sql_value()}
%% @doc
%%   Reads a row from Tbl table in Db database such that the Value 
%%   matches the value in Column. ColValue must have the same type 
%%   as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec read_timeout(atom(), atom(), {atom(), sql_value()}, timeout()) -> sql_result().
read_timeout(Db, Tbl, {Column, Value}, Timeout) ->
    gen_server:call(Db, {read, Tbl, Column, Value}, Timeout).

%%--------------------------------------------------------------------
%% @spec read_timeout(Db, Tbl, Key, Columns, Timeout :: timeout()) -> [any()]
%%        Db = atom()
%%        Tbl = atom()
%%        Key = {Column :: atom(), Value :: sql_value()}
%%        Columns = [atom()]
%% @doc
%%    Reads a row from Tbl table in Db database such that the Value
%%    matches the value in Column. Value must have the same type as 
%%    determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec read_timeout(atom(), atom(), {atom(), sql_value()}, [atom()], timeout()) -> sql_result().
read_timeout(Db, Tbl, {Key, Value}, Columns, Timeout) ->
    gen_server:call(Db, {read, Tbl, Key, Value, Columns}, Timeout).

%%--------------------------------------------------------------------
%% @spec delete(Tbl :: atom(), Key) -> any()
%%        Key = {Column :: atom(), Value :: sql_value()}
%% @doc
%%   Delete a row from Tbl table in Db database such that the Value 
%%   matches the value in Column. 
%%   Value must have the same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec delete(atom(), {atom(), sql_value()}) -> sql_non_query_result().
delete(Tbl, Key) ->
    delete(?MODULE, Tbl, Key).

%%--------------------------------------------------------------------
%% @spec delete_timeout(Db :: atom(), Tbl :: atom(), Key, Timeout :: timeout()) -> sql_non_query_result()
%%        Key = {Column :: atom(), Value :: sql_value()}
%% @doc
%%   Delete a row from Tbl table in Db database such that the Value 
%%   matches the value in Column. 
%%   Value must have the same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec delete_timeout(atom(), atom(), {atom(), any()}, timeout()) -> sql_non_query_result().
delete_timeout(Db, Tbl, Key, Timeout) ->
    gen_server:call(Db, {delete, Tbl, Key}, Timeout).

%%--------------------------------------------------------------------
%% @spec delete(Db :: atom(), Tbl :: atom(), Key) -> sql_non_query_result()
%%        Key = {Column :: atom(), Value :: sql_value()}
%% @doc
%%   Delete a row from Tbl table in Db database such that the Value 
%%   matches the value in Column. 
%%   Value must have the same type as determined from table_info/3.
%% @end
%%--------------------------------------------------------------------
-spec delete(atom(), atom(), {atom(), any()}) -> sql_non_query_result().
delete(Db, Tbl, Key) ->
    gen_server:call(Db, {delete, Tbl, Key}).

%%--------------------------------------------------------------------
%% @spec drop_table(Tbl :: atom()) -> sql_non_query_result()
%% @doc
%%   Drop the table Tbl.
%% @end
%%--------------------------------------------------------------------
-spec drop_table(atom()) -> sql_non_query_result().
drop_table(Tbl) ->
    drop_table(?MODULE, Tbl).

%%--------------------------------------------------------------------
%% @spec drop_table(Db :: atom(), Tbl :: atom()) -> sql_non_query_result()
%% @doc
%%   Drop the table Tbl from Db database.
%% @end
%%--------------------------------------------------------------------
-spec drop_table(atom(), atom()) -> sql_non_query_result().
drop_table(Db, Tbl) ->
    gen_server:call(Db, {drop_table, Tbl}).

%%--------------------------------------------------------------------
%% @spec drop_table_timeout(Db :: atom(), Tbl :: atom(), Timeout :: timeout()) -> sql_non_query_result()
%% @doc
%%   Drop the table Tbl from Db database.
%% @end
%%--------------------------------------------------------------------
-spec drop_table_timeout(atom(), atom(), timeout()) -> sql_non_query_result().
drop_table_timeout(Db, Tbl, Timeout) ->
    gen_server:call(Db, {drop_table, Tbl}, Timeout).

%%--------------------------------------------------------------------
%% @spec vacuum() -> sql_non_query_result()
%% @doc
%%   Vacuum the default database.
%% @end
%%--------------------------------------------------------------------
-spec vacuum() -> sql_non_query_result().
vacuum() ->
    gen_server:call(?MODULE, vacuum).

%%--------------------------------------------------------------------
%% @spec vacuum(Db :: atom()) -> sql_non_query_result()
%% @doc
%%   Vacuum the Db database.
%% @end
%%--------------------------------------------------------------------
-spec vacuum(atom()) -> sql_non_query_result().
vacuum(Db) ->
    gen_server:call(Db, vacuum).

%%--------------------------------------------------------------------
%% @spec vacuum_timeout(Db :: atom(), Timeout :: timeout()) -> sql_non_query_result()
%% @doc
%%   Vacuum the Db database.
%% @end
%%--------------------------------------------------------------------
-spec vacuum_timeout(atom(), timeout()) -> sql_non_query_result().
vacuum_timeout(Db, Timeout) ->
    gen_server:call(Db, vacuum, Timeout).

%% %%--------------------------------------------------------------------
%% %% @spec create_function(Db :: atom(), FunctionName :: atom(), Function :: function()) -> term()
%% %% @doc
%% %%   Creates function under name FunctionName.
%% %%
%% %% @end
%% %%--------------------------------------------------------------------
%% -spec create_function(atom(), atom(), function()) -> any().
%% create_function(Db, FunctionName, Function) ->
%%     gen_server:call(Db, {create_function, FunctionName, Function}).

%%--------------------------------------------------------------------
%% @spec value_to_sql_unsafe(Value :: sql_value()) -> iolist()
%% @doc
%%    Converts an Erlang term to an SQL string.
%%    Currently supports integers, floats, 'null' atom, and iodata
%%    (binaries and iolists) which are treated as SQL strings.
%%
%%    Note that it opens opportunity for injection if an iolist includes
%%    single quotes! Replace all single quotes (') with '' manually, or
%%    use value_to_sql/1 if you are not sure if your strings contain
%%    single quotes (e.g. can be entered by users).
%%
%%    Reexported from sqlite3_lib:value_to_sql/1 for user convenience.
%% @end
%%--------------------------------------------------------------------
-spec value_to_sql_unsafe(sql_value()) -> iolist().
value_to_sql_unsafe(X) -> sqlite3_lib:value_to_sql_unsafe(X).

%%--------------------------------------------------------------------
%% @spec value_to_sql(Value :: sql_value()) -> iolist()
%% @doc
%%    Converts an Erlang term to an SQL string.
%%    Currently supports integers, floats, 'null' atom, and iodata
%%    (binaries and iolists) which are treated as SQL strings.
%%
%%    All single quotes (') will be replaced with ''.
%%
%%    Reexported from sqlite3_lib:value_to_sql/1 for user convenience.
%% @end
%%--------------------------------------------------------------------
-spec value_to_sql(sql_value()) -> iolist().
value_to_sql(X) -> sqlite3_lib:value_to_sql(X).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% @spec init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% @doc Initiates the server
%% @end
%% @hidden
%%--------------------------------------------------------------------

% -type init_return() :: {'ok', tuple()} | {'ok', tuple(), integer()} | 'ignore' | {'stop', any()}.

-spec init([any()]) -> {'ok', #state{}} | {'stop', string()}.
init(Options) ->
    DbFile = proplists:get_value(file, Options),
    PrivDir = get_priv_dir(),
    case erl_ddll:load(PrivDir, atom_to_list(?DRIVER_NAME)) of
        ok ->
            Port = open_port({spawn, create_port_cmd(DbFile)}, [binary]),
            {ok, #state{port = Port, ops = Options}};
        {error, permanent} -> %% already loaded!
            Port = open_port({spawn, create_port_cmd(DbFile)}, [binary]),
            {ok, #state{port = Port, ops = Options}};            
        {error, Error} ->
            Msg = io_lib:format("Error loading ~p: ~s", 
                                [?DRIVER_NAME, erl_ddll:format_error(Error)]),
            {stop, lists:flatten(Msg)}
    end.

%%--------------------------------------------------------------------
%% @spec handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% @doc Handling call messages
%% @end
%% @hidden
%%--------------------------------------------------------------------

%% -type handle_call_return() :: {reply, any(), tuple()} | {reply, any(), tuple(), integer()} |
%%       {noreply, tuple()} | {noreply, tuple(), integer()} |
%%       {stop, any(), any(), tuple()} | {stop, any(), tuple()}.

-spec handle_call(any(), pid(), #state{}) -> {'reply', any(), #state{}} | {'stop', 'normal', 'ok', #state{}}.
handle_call(close, _From, State) ->
    Reply = ok,
    {stop, normal, Reply, State};
handle_call(list_tables, _From, State) ->
    SQL = "select name from sqlite_master where type='table';",
    Data = do_sql_exec(SQL, State),
    TableList = proplists:get_value(rows, Data),
    TableNames = [erlang:list_to_atom(erlang:binary_to_list(Name)) || {Name} <- TableList],
    {reply, TableNames, State};
handle_call({table_info, Tbl}, _From, State) ->
    % make sure we only get table info.
    % SQL Injection warning
    SQL = io_lib:format("select sql from sqlite_master where tbl_name = '~p' and type='table';", [Tbl]),
    Data = do_sql_exec(SQL, State),
    TableSql = proplists:get_value(rows, Data),
    case TableSql of
        [{Info}] ->
            ColumnList = parse_table_info(binary_to_list(Info)),
            {reply, ColumnList, State};
        [] ->
            {reply, table_does_not_exist, State}
    end;
handle_call({create_function, FunctionName, Function}, _From, #state{port = Port} = State) ->
    Reply = exec(Port, {create_function, FunctionName, Function}),
    {reply, Reply, State};
handle_call({sql_exec, SQL}, _From, State) ->
    do_handle_call_sql_exec(SQL, State);
handle_call({sql_bind_and_exec, SQL, Params}, _From, State) ->
    Reply = do_sql_bind_and_exec(SQL, Params, State),
    {reply, Reply, State};
handle_call({sql_exec_script, SQL}, _From, State) ->
    Reply = do_sql_exec_script(SQL, State),
    {reply, Reply, State};
handle_call({create_table, Tbl, Columns}, _From, State) ->
    SQL = sqlite3_lib:create_table_sql(Tbl, Columns),
    do_handle_call_sql_exec(SQL, State);
handle_call({create_table, Tbl, Columns, Constraints}, _From, State) ->
    SQL = sqlite3_lib:create_table_sql(Tbl, Columns, Constraints),
    do_handle_call_sql_exec(SQL, State);
handle_call({update, Tbl, Key, Value, Data}, _From, State) ->
    SQL = sqlite3_lib:update_sql(Tbl, Key, Value, Data),
    do_handle_call_sql_exec(SQL, State);
handle_call({write, Tbl, Data}, _From, State) ->
    % insert into t1 (data,num) values ('This is sample data',3);
    SQL = sqlite3_lib:write_sql(Tbl, Data),
    do_handle_call_sql_exec(SQL, State);
handle_call({write_many, Tbl, DataList}, _From, State) ->
    do_sql_exec("BEGIN;", State),
    [do_sql_exec(sqlite3_lib:write_sql(Tbl, Data), State) || Data <- DataList],
    do_handle_call_sql_exec("COMMIT;", State);
handle_call({read, Tbl}, _From, State) ->
    % select * from  Tbl where Key = Value;
    SQL = sqlite3_lib:read_sql(Tbl),
    do_handle_call_sql_exec(SQL, State);
handle_call({read, Tbl, Columns}, _From, State) ->
    SQL = sqlite3_lib:read_sql(Tbl, Columns),
    do_handle_call_sql_exec(SQL, State);
handle_call({read, Tbl, Key, Value}, _From, State) ->
    % select * from  Tbl where Key = Value;
    SQL = sqlite3_lib:read_sql(Tbl, Key, Value),
    do_handle_call_sql_exec(SQL, State);
handle_call({read, Tbl, Key, Value, Columns}, _From, State) ->
    SQL = sqlite3_lib:read_sql(Tbl, Key, Value, Columns),
    do_handle_call_sql_exec(SQL, State);
handle_call({delete, Tbl, {Key, Value}}, _From, State) ->
    % delete from Tbl where Key = Value;
    SQL = sqlite3_lib:delete_sql(Tbl, Key, Value),
    do_handle_call_sql_exec(SQL, State);
handle_call({drop_table, Tbl}, _From, State) ->
    SQL = sqlite3_lib:drop_table_sql(Tbl),
    do_handle_call_sql_exec(SQL, State);
handle_call({prepare, SQL}, _From, State = #state{port = Port, refs = Refs}) ->
    case exec(Port, {prepare, SQL}) of
        Index when is_integer(Index) ->
            Ref = erlang:make_ref(),
            Reply = {ok, Ref},
            NewState = State#state{refs = dict:store(Ref, Index, Refs)};
        Error ->
            Reply = Error,
            NewState = State
    end,
    {reply, Reply, NewState};
handle_call({bind, Ref, Params}, _From, State = #state{port = Port, refs = Refs}) ->
    Index = dict:fetch(Ref, Refs),
    Reply = exec(Port, {bind, Index, Params}),
    {reply, Reply, State};
handle_call({finalize, Ref}, _From, State = #state{port = Port, refs = Refs}) ->
    Index = dict:fetch(Ref, Refs),
    case exec(Port, {finalize, Index}) of
        ok ->
            Reply = ok,
            NewState = State#state{refs = dict:erase(Ref, Refs)};
        Error ->
            Reply = Error,
            NewState = State
    end,
    {reply, Reply, NewState};
handle_call({Cmd, Ref}, _From, State = #state{port = Port, refs = Refs}) ->
    Reply = case dict:find(Ref, Refs) of
                {ok, Index} ->
                    exec(Port, {Cmd, Index});
                error ->
                    {error, -1, 
                     "Bad reference to prepared statement; it is already finalized or doesn't exist"}
            end,
    {reply, Reply, State};
handle_call(vacuum, _From, State) ->
    SQL = "VACUUM;",
    do_handle_call_sql_exec(SQL, State);
handle_call(_Request, _From, State) ->
    Reply = unknown_request,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% @doc Handling cast messages
%% @end
%% @hidden
%%--------------------------------------------------------------------

%% -type handle_cast_return() :: {noreply, tuple()} | {noreply, tuple(), integer()} |
%%       {stop, any(), tuple()}.

-spec handle_cast(any(), #state{}) -> {'noreply', #state{}}.
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% @doc Handling all non call/cast messages
%% @end
%% @hidden
%%--------------------------------------------------------------------
-spec handle_info(any(), #state{}) -> {'noreply', #state{}}.
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @spec terminate(Reason, State) -> term()
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% @end
%% @hidden
%%--------------------------------------------------------------------
-spec terminate(atom(), tuple()) -> term().
terminate(_Reason, #state{port = Port}) ->
    case Port of
        undefined ->
            pass;
        _ ->
            port_command(Port, term_to_binary({close, nop})),
            port_close(Port)
    end,
    case erl_ddll:unload(?DRIVER_NAME) of
        ok -> 
            ok;
        {error, permanent} ->
            ok; %% FIXME is this the correct behavior?
        {error, ErrorDesc} ->
            error_logger:error_msg("Error unloading sqlite3 driver: ~s~n", 
                                   [erl_ddll:format_error(ErrorDesc)])
    end,
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @doc Convert process state when code is changed
%% @end
%% @hidden
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

get_priv_dir() ->
    case code:priv_dir(sqlite3) of
        {error, bad_name} ->
            %% application isn't in path, fall back
            {?MODULE, _, FileName} = code:get_object_code(?MODULE),
            filename:join(filename:dirname(FileName), "../priv");
        Dir ->
            Dir
    end.

-define(SQL_EXEC_COMMAND, 2).
-define(SQL_CREATE_FUNCTION, 3).
-define(SQL_BIND_AND_EXEC_COMMAND, 4).
-define(PREPARE, 5).
-define(PREPARED_BIND, 6).
-define(PREPARED_STEP, 7).
-define(PREPARED_RESET, 8).
-define(PREPARED_CLEAR_BINDINGS, 9).
-define(PREPARED_FINALIZE, 10).
-define(PREPARED_COLUMNS, 11).
-define(SQL_EXEC_SCRIPT, 12).

create_port_cmd(DbFile) ->
    atom_to_list(?DRIVER_NAME) ++ " " ++ DbFile.

do_handle_call_sql_exec(SQL, State) ->
    Reply = do_sql_exec(SQL, State),
    {reply, Reply, State}.

do_sql_exec(SQL, #state{port = Port}) ->
    ?dbgF("SQL: ~s~n", [SQL]),
    exec(Port, {sql_exec, SQL}).

do_sql_bind_and_exec(SQL, Params, #state{port = Port}) ->
    ?dbgF("SQL: ~s; Parameters: ~p~n", [SQL, Params]),
    exec(Port, {sql_bind_and_exec, SQL, Params}).

do_sql_exec_script(SQL, #state{port = Port}) ->
    ?dbgF("SQL: ~s~n", [SQL]),
    exec(Port, {sql_exec_script, SQL}).

exec(_Port, {create_function, _FunctionName, _Function}) ->
    error_logger:error_report([{application, sqlite3}, "NOT IMPL YET"]);
%port_control(Port, ?SQL_CREATE_FUNCTION, list_to_binary(Cmd)),
%wait_result(Port);
exec(Port, {sql_exec, SQL}) ->
    port_control(Port, ?SQL_EXEC_COMMAND, SQL),
    wait_result(Port);
exec(Port, {sql_bind_and_exec, SQL, Params}) ->
    Bin = term_to_binary({iolist_to_binary(SQL), Params}),
    port_control(Port, ?SQL_BIND_AND_EXEC_COMMAND, Bin),
    wait_result(Port);
exec(Port, {sql_exec_script, SQL}) ->
    port_control(Port, ?SQL_EXEC_SCRIPT, SQL),
    wait_result(Port);
exec(Port, {prepare, SQL}) ->
    port_control(Port, ?PREPARE, SQL),
    wait_result(Port);
exec(Port, {bind, Index, Params}) ->
    Bin = term_to_binary({Index, Params}),
    port_control(Port, ?PREPARED_BIND, Bin),
    wait_result(Port);
exec(Port, {Cmd, Index}) when is_integer(Index) ->
    CmdCode = case Cmd of
                  next -> ?PREPARED_STEP;
                  reset -> ?PREPARED_RESET;
                  clear_bindings -> ?PREPARED_CLEAR_BINDINGS;
                  finalize -> ?PREPARED_FINALIZE;
                  columns -> ?PREPARED_COLUMNS
              end,
    Bin = term_to_binary(Index),
    port_control(Port, CmdCode, Bin),
    wait_result(Port).

wait_result(Port) ->
    receive
        {Port, Reply} ->
            case Reply of
                {error, Code, Reason} ->
                    error_logger:error_msg("sqlite3 driver error: ~s~n", 
                                           [Reason]),
                    % ?dbg("Error: ~p~n", [Reason]),
                    {error, Code, Reason};
                _ ->
                    % ?dbg("Reply: ~p~n", [Reply]),
                    Reply
            end;
        {'EXIT', Port, Reason} ->
            error_logger:error_msg("sqlite3 driver port closed with reason ~p~n", 
                                   [Reason]),
            % ?dbg("Error: ~p~n", [Reason]),
            {error, -1, Reason};
        Other when is_tuple(Other), element(1, Other) =/= '$gen_call', element(1, Other) =/= '$gen_cast' ->
            error_logger:error_msg("sqlite3 unexpected reply ~p~n", 
                                   [Other]),
            Other
    end.

parse_table_info(Info) ->
    [_, Tail] = string:tokens(Info, "()"),
    Cols = string:tokens(Tail, ","),
    build_table_info(lists:map(fun(X) ->
                         string:tokens(X, " ") 
                     end, Cols), []).
   
build_table_info([], Acc) -> 
    lists:reverse(Acc);
build_table_info([[ColName, ColType] | Tl], Acc) -> 
    build_table_info(Tl, [{list_to_atom(ColName), sqlite3_lib:col_type_to_atom(ColType)}| Acc]); 
build_table_info([[ColName, ColType | Constraints] | Tl], Acc) ->
    build_table_info(Tl, [{list_to_atom(ColName), sqlite3_lib:col_type_to_atom(ColType), build_constraints(Constraints)} | Acc]).

%% TODO conflict-clause parsing
build_constraints([]) -> [];
build_constraints(["PRIMARY", "KEY" | Tail]) -> 
    {Constraint, Rest} = build_primary_key_constraint(Tail),
    [Constraint | build_constraints(Rest)];
build_constraints(["UNIQUE" | Tail]) -> [unique | build_constraints(Tail)];
build_constraints(["NOT", "NULL" | Tail]) -> [not_null | build_constraints(Tail)];
build_constraints(["DEFAULT", DefaultValue | Tail]) -> [{default, sqlite3_lib:sql_to_value(DefaultValue)} | build_constraints(Tail)].
% build_constraints(["CHECK", Check | Tail]) -> ...
% build_constraints(["REFERENCES", Check | Tail]) -> ...

build_primary_key_constraint(Tokens) -> build_primary_key_constraint(Tokens, []).

build_primary_key_constraint(["ASC" | Rest], Acc) ->
    build_primary_key_constraint(Rest, [asc | Acc]);
build_primary_key_constraint(["DESC" | Rest], Acc) ->
    build_primary_key_constraint(Rest, [desc | Acc]);
build_primary_key_constraint(["AUTOINCREMENT" | Rest], Acc) ->
    build_primary_key_constraint(Rest, [autoincrement | Acc]);
build_primary_key_constraint(Tail, []) ->
    {primary_key, Tail};
build_primary_key_constraint(Tail, Acc) ->
    {{primary_key, lists:reverse(Acc)}, Tail}.

%% conflict_clause(["ON", "CONFLICT", ResolutionString | Tail]) ->
%%     Resolution = case ResolutionString of
%%                      "ROLLBACK" -> rollback;
%%                      "ABORT" -> abort;
%%                      "FAIL" -> fail;
%%                      "IGNORE" -> ignore;
%%                      "REPLACE" -> replace
%%                  end,
%%     {{on_conflict, Resolution}, Tail};
%% conflict_clause(NoOnConflictClause) ->
%%     {no_on_conflict, NoOnConflictClause}.

%%--------------------------------------------------------------------
%% @type sql_value() = null | number() | iodata() | {blob, binary()}.
%% 
%% Values accepted in SQL statements are atom 'null', numbers, 
%% strings (represented as iodata()) and blobs.
%% @end
%% @type sql_type() = integer | text | double | blob | atom() | string().
%% 
%% Types of SQLite columns are represented by atoms 'integer', 'text', 'double',
%% 'blob'. Other atoms and strings may also be used (e.g. "VARCHAR(20)", 'smallint', etc.)
%% See [http://www.sqlite.org/datatype3.html].
%% @end
%% @type pk_constraint() = autoincrement | desc | asc.
%% See {@link pk_constraints()}.
%% @type pk_constraints() = pk_constraint() | [pk_constraint()].
%% See {@link column_constraint()}.
%% @type column_constraint() = non_null | primary_key | {primary_key, pk_constraints()}
%%                             | unique | {default, sql_value()}.
%% See {@link column_constraints()}.
%% @type column_constraints() = column_constraint() | [column_constraint()].
%% See {@link table_info()}.
%% @type table_info() = [{atom(), sql_type()} | {atom(), sql_type(), column_constraints()}].
%% 
%% Describes the columns of an SQLite table: each tuple contains name, type and constraints (if any)
%% of one column.
%% @end
%% @type table_constraint() = {primary_key, [atom()]} | {unique, [atom()]}.
%% @type table_constraints() = table_constraint() | [table_constraint()].
%% 
%% Currently supported constraints for {@link table_info()} and {@link sqlite3:create_table/4}.
%% @end
%% @type sqlite_error() = {'error', integer(), string()}.
%% 
%% Errors are reported by their SQLite result code 
%% ([http://www.sqlite.org/c3ref/c_busy_recovery.html]) and a string containing 
%% English-language text that describes the error.
%% @end
%% @type sql_non_query_result() = ok | sqlite_error() | {rowid, integer()}.
%% The result returned by functions which call the database but don't return
%% any records.
%% @end
%% @type sql_result() = sql_non_query_result() | [{columns, [string()]} | {rows, [tuple()]}].
%% The result returned by functions which query the database.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
