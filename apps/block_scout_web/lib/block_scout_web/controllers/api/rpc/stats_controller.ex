defmodule BlockScoutWeb.API.RPC.StatsController do
  use BlockScoutWeb, :controller

  alias Explorer.{Chain, Etherscan, Market}
  alias Explorer.Chain.Cache.Counters.{AddressesCoinBalanceSum, AddressesCoinBalanceSumMinusBurnt, LastFetchedCounter}
  alias Explorer.Chain.Wei

  @cmc_token_supply_precision 9

  def tokensupply(conn, params) do
    with {:contractaddress_param, {:ok, contractaddress_param}} <- fetch_contractaddress(params),
         {:format, {:ok, address_hash}} <- to_address_hash(contractaddress_param),
         {:token, {:ok, token}} <- {:token, Chain.token_from_address_hash(address_hash)} do
      if Map.get(params, "cmc") == "true" do
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          200,
          token.total_supply &&
            to_cmc_total_supply(
              token.total_supply,
              token.decimals
            )
        )
      else
        conn
        |> render(
          "tokensupply.json",
          total_supply: token.total_supply && Decimal.to_string(token.total_supply)
        )
      end
    else
      {:contractaddress_param, :error} ->
        render(conn, :error, error: "Query parameter contract address is required")

      {:format, :error} ->
        render(conn, :error, error: "Invalid contract address format")

      {:token, {:error, :not_found}} ->
        render(conn, :error, error: "Contract address not found")
    end
  end

  def ethsupplyexchange(conn, _params) do
    wei_total_supply =
      Chain.total_supply()
      |> Decimal.new()
      |> Wei.from(:ether)
      |> Wei.to(:wei)
      |> Decimal.to_string()

    render(conn, "ethsupplyexchange.json", total_supply: wei_total_supply)
  end

  def ethsupply(conn, _params) do
    cached_wei_total_supply = AddressesCoinBalanceSum.get_sum()

    render(conn, "ethsupply.json", total_supply: cached_wei_total_supply)
  end

  def coinsupply(conn, _params) do
    cached_coin_total_supply_wei = AddressesCoinBalanceSumMinusBurnt.get_sum_minus_burnt()

    coin_total_supply_wei =
      if Decimal.compare(cached_coin_total_supply_wei, 0) == :gt do
        cached_coin_total_supply_wei
      else
        LastFetchedCounter.get("sum_coin_total_supply_minus_burnt")
      end

    cached_coin_total_supply =
      %Wei{value: Decimal.new(coin_total_supply_wei)}
      |> Wei.to(:ether)
      |> Decimal.to_string(:normal)

    render(conn, "coinsupply.json", total_supply: cached_coin_total_supply)
  end

  def ethprice(conn, _params) do
    rates = Market.get_coin_exchange_rate()

    render(conn, "ethprice.json", rates: rates)
  end

  def coinprice(conn, _params) do
    rates = Market.get_coin_exchange_rate()

    render(conn, "coinprice.json", rates: rates)
  end

  defp fetch_contractaddress(params) do
    {:contractaddress_param, Map.fetch(params, "contractaddress")}
  end

  defp to_address_hash(address_hash_string) do
    {:format, Chain.string_to_address_hash(address_hash_string)}
  end

  @spec to_cmc_total_supply(Decimal.t(), Decimal.t() | nil) :: String.t()
  defp to_cmc_total_supply(total_supply, decimals) do
    divider =
      1
      |> Decimal.new(1, Decimal.to_integer(decimals || Decimal.new(0)))
      |> Decimal.to_integer()

    total_supply
    |> Decimal.div(divider)
    |> Decimal.round(@cmc_token_supply_precision)
    |> Decimal.to_string()
  end

  def totalfees(conn, params) do
    case Map.fetch(params, "date") do
      {:ok, date} ->
        case Etherscan.get_total_fees_per_day(date) do
          {:ok, total_fees} -> render(conn, "totalfees.json", total_fees: total_fees)
          {:error, error} -> render(conn, :error, error: error)
        end

      _ ->
        render(conn, :error, error: "Required date input is missing.")
    end
  end
end
