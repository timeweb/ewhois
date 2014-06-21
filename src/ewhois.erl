-module(ewhois).

-export([query/1]).
-export([query/2]).

-define(IANAHOST, "whois.iana.org").
-define(TIMEOUT, 10000).
-define(PORT, 43).
-define(OPTS, [{port, ?PORT}, {timeout, ?TIMEOUT}]).

query(Domain) ->
    query(Domain, ?OPTS).

query(Domain, Opts) when is_binary(Domain), is_list(Opts) ->
    Nic = proplists:get_value(nic, Opts, get_root_nics(Domain)),
    case send_query(Domain, Nic, Opts) of
        {ok, Reply} ->
            response(Reply, Opts);
        {error, Reason} ->
            {error, Reason}
    end.


response(RawData, [raw | _T]) ->
    RawData;
response(RawData, [vals | _T]) ->
    ewhois_parser:parse_vals(RawData);
response(RawData, _Opts) ->
    ewhois_parser:bind(RawData).


send_query(Domain, Nic, Opts) when is_list(Nic) ->
    Port = proplists:get_value(port, Opts, ?PORT),
    Timeout = proplists:get_value(timeout, Opts, ?TIMEOUT),
    case gen_tcp:connect(Nic, Port, [binary, {packet, 0}, {send_timeout, Timeout}], Timeout) of
        {ok, Sock} ->
            ok = gen_tcp:send(Sock, iolist_to_binary([Domain, <<"\r\n">>])),
            Reply = wait_reply(Sock, Timeout),
            ok = gen_tcp:close(Sock),
            {ok, Reply};
        {error, Reason} ->
            {error, Reason}
    end.


wait_reply(Sock, Timeout) ->
    receive
        {tcp, Sock, Data} ->
            Data
    after Timeout ->
            {error, timeout}
    end.


get_root_nics(Domain) ->
    case send_query(Domain, ?IANAHOST, ?OPTS) of
        {ok, Result} ->
            case re:run(Result, <<"refer:\s+(.*)\n">>, [{capture, [1], binary}]) of
                {match, [Refer]} ->
                    binary_to_list(Refer);
                nomatch ->
                    {error, not_found_root_nics}
            end;
        {error, Reason} ->
            {error, Reason}
    end.