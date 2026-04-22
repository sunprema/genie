defmodule Genie.Accounts do
  use Ash.Domain, otp_app: :genie, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Genie.Accounts.Organisation
    resource Genie.Accounts.Token
    resource Genie.Accounts.User
    resource Genie.Accounts.ApiKey
  end
end
