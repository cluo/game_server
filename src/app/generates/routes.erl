%%%===================================================================
%%% Generated by generate_api.rb 2014-03-10 13:41:56 +0800
%%%===================================================================
-module(routes).
-export([route/1]).

route(3) ->
    {sessions_controller, login};
route(4) ->
    {users_controller, public_info}.
