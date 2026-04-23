defmodule Genie.Conversation do
  @moduledoc false
  use Ash.Domain, otp_app: :genie

  resources do
    resource Genie.Conversation.Session
    resource Genie.Conversation.Turn
  end
end
