defmodule Genie.Conversation do
  use Ash.Domain, otp_app: :genie

  resources do
    resource Genie.Conversation.Session
    resource Genie.Conversation.Turn
  end
end
