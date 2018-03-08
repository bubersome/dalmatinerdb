-module(metric_io_worker).

-behaviour(riak_core_vnode_worker).
-include("metric_io.hrl").

-export([init_worker/3,
         handle_work/3]).

-record(state, {index, node}).

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Initialize the worker. Currently only the VNode index
%% parameter is used.
init_worker(VNodeIndex, _Args, _Props) ->
    {ok, #state{index=VNodeIndex, node = node()}}.

%% @doc Perform the asynchronous fold operation.
handle_work(#read_req{
               mstore      = MSetc,
               metric      = Metric,
               time        = Time,
               count       = Count,
               compression = Compression,
               map_fn      = Map,
               req_id      = ReqID,
               hpts        = HPTS
              }, _Sender, State = #state{index = P, node = N}) ->
    HPTSOpts = case HPTS of
                   true ->
                       [with_timestamp];
                   false ->
                       []
               end,
    {ok, Data} = ddb_histogram:timed_update(
                   {mstore, read},
                   mstore, get, [MSetc, Metric, Time, Count,
                                 [one_off | HPTSOpts]]),
    mstore:close(MSetc),
    Data1 = case Map of
                undefined -> Data;
                _         -> Map(Data)
            end,
    Dc = compress(Data1, Compression),
    {reply, {ok, ReqID, {P, N}, Dc}, State}.

compress(Data, snappy) ->
    {ok, Dc} = snappiest:compress(Data),
    Dc;
compress(Data, none) ->
    Data.
