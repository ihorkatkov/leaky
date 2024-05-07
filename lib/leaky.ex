defmodule Leaky do
  @moduledoc """
  Implements a token-based rate limiter using the leaky bucket algorithm, ideal for controlling access rates to resources in Elixir applications.
  This implementation leverages ETS for optimized performance, making it suitable for high-load environments.

  ## Overview

  The leaky bucket algorithm helps smooth out bursty traffic by limiting the rate at which actions are taken.
  It's like a bucket with a hole: tokens, representing permissions to take an action, drip out at a constant rate.
  If the bucket is full, new actions must wait, ensuring the overall rate does not exceed the desired threshold.
  Read more about the algorithm here: https://en.wikipedia.org/wiki/Leaky_bucket

  ## Usage

  The rate limiter process can be customized with several options:
  - `bucket_name`: Unique identifier for the bucket.
  - `max_accumulated`: The maximum tokens the bucket can hold. Once full, new tokens will not accumulate.
  - `refill`: The number of tokens added to the bucket on each refill cycle.
  - `interval`: The time (in ms) between each refill cycle. Defaults to 1000 ms.
  - `name`: The GenServer process name. Defaults to `Leaky`.

  ```elixir
    configuration = [bucket_name: :user_requests, max_accumulated: 100, refill: 10, interval: 1000]
    {:ok, _pid} = Leaky.start_link(configuration)
  ```

  To attempt an action, checking if it's allowed under the current rate:
  ```elixir
    case Leaky.acquire(:user_requests, 1) do
      {:allow, tokens_left} -> "Action allowed."
      :deny ->"Action denied."
    end
  ```
  """
  use GenServer

  @type bucket :: integer | binary | tuple | atom

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            refill: integer,
            initial: integer,
            interval: integer,
            max_accumulated: integer,
            name: GenServer.name()
          }

    defstruct [:bucket_name, :refill, :max_accumulated, :initial, :interval, :name]
  end

  @doc """
  The function evaluates whether a particular action can proceed without violating the configured rate limit of the bucket.
  It is designed to ensure that the frequency of actions does not exceed the predetermined limits, thus preventing system overload or abuse.

  ## Examples

  ```elixir
  .  case Leaky.acquire(:user_requests, 1) do
      {:allow, tokens_left} -> "Action allowed."
      :deny ->"Action denied."
    end
  ```
  """
  @spec acquire(bucket :: bucket(), cost :: integer, name :: GenServer.name()) ::
          {:allow, integer} | :deny
  def acquire(bucket, cost, name \\ __MODULE__) do
    GenServer.call(name, {:acquire, bucket, cost})
  end

  @doc """
  The function retrieves the current number of available tokens in the specified bucket,
  providing insight into the bucket's current state without altering it.
  It accepts the bucket identifier and an optional name parameter for the GenServer managing the rate limiter's state,
  returning either the number of tokens left or nil if the bucket does not exist.
  This function is useful for monitoring and debugging purposes, allowing developers to assess the rate limiter's status at any given moment.

  ## Example

  ```
   iex> Leaky.inspect(:user_requests)
   iex> 3
  ```
  """
  @spec inspect(bucket :: bucket(), name :: GenServer.name()) :: integer | nil
  def inspect(bucket, name \\ __MODULE__) do
    case GenServer.call(name, {:acquire, bucket, 0}) do
      {:allow, tokens_left} -> tokens_left
      :deny -> 0
    end
  end

  @doc """
  The function adjusts the number of tokens in a specified bucket by either adding (incrementing) or removing (decrementing) tokens,
  directly influencing the bucket's current capacity without performing a rate check.
  """
  @spec adjust_tokens(bucket :: bucket(), amount :: integer, name :: GenServer.name()) :: :ok
  def adjust_tokens(bucket, amount, name \\ __MODULE__) do
    GenServer.cast(name, {:increment_tokens_left, bucket, amount})
  end

  @doc """
  Updates the configuration of the rate limiter process. Changes are applied immediately, affecting the rate limiter's behavior.
  It is useful for dynamically adjusting the rate limiter's settings without restarting the process.

  Options which can be updated: `max_accumulated`, `interval`, and `refill`.


  ## Example

  ```
  iex> Leaky.update_configuration(max_accumulated: 10, refill: 2, interval: 5)
  :ok
  iex> {:allow, 8} == Leaky.acquire(:user_requests, 2)
  true
  ```

  """
  @spec update_configuration(opts :: Keyword.t(), name :: GenServer.name()) :: :ok
  def update_configuration(opts, name \\ __MODULE__) do
    GenServer.cast(name, {:update_configuration, opts})
  end

  def start_link(opts) do
    bucket_name = Keyword.fetch!(opts, :bucket_name)
    max_accumulated = Keyword.fetch!(opts, :max_accumulated)
    refill = Keyword.fetch!(opts, :refill)
    interval = Keyword.get(opts, :interval, 1_000)
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(
      __MODULE__,
      %State{
        bucket_name: bucket_name,
        max_accumulated: max_accumulated,
        interval: interval,
        refill: refill
      },
      name: name
    )
  end

  @impl GenServer
  def init(%State{} = state) do
    create_ets_table(state)

    {:ok, state}
  end

  defp create_ets_table(%State{} = state) do
    :ets.new(state.bucket_name, [
      :named_table,
      :set
    ])
  end

  @impl GenServer
  def handle_cast({:increment_tokens_left, bucket, amount}, %State{} = state) do
    now = :erlang.system_time(:milli_seconds)
    table = state.bucket_name

    case :ets.lookup(table, bucket) do
      [] ->
        :ets.insert(table, {bucket, state.max_accumulated + amount, now})

        :ok

      [{bucket, tokens, last_time}] ->
        accumulated_tokens = calculate_accumulated_tokens(tokens, now, last_time, state)
        tokens_left = accumulated_tokens + amount

        :ets.update_element(table, bucket, [{2, tokens_left}, {3, now}])
    end

    {:noreply, state}
  end

  def handle_cast({:update_configuration, opts}, %State{} = state) do
    max_accumulated = Keyword.get(opts, :max_accumulated, state.max_accumulated)
    interval = Keyword.get(opts, :interval, state.interval)
    refill = Keyword.get(opts, :refill, state.refill)

    {:noreply, %{state | max_accumulated: max_accumulated, interval: interval, refill: refill}}
  end

  @impl GenServer
  def handle_call({:acquire, bucket, cost}, _from, %State{} = state) do
    now = :erlang.system_time(:milli_seconds)
    table = state.bucket_name

    response =
      case :ets.lookup(table, bucket) do
        [] ->
          tokens_left = state.max_accumulated - cost

          :ets.insert(table, {bucket, tokens_left, now})

          {:allow, tokens_left}

        [{bucket, tokens, last_time}] ->
          accumulated_tokens = calculate_accumulated_tokens(tokens, now, last_time, state)
          tokens_left = accumulated_tokens - cost

          if tokens_left < 0 do
            :deny
          else
            :ets.update_element(table, bucket, [{2, tokens_left}, {3, now}])

            {:allow, tokens_left}
          end
      end

    {:reply, response, state}
  end

  defp calculate_accumulated_tokens(tokens, now, last_inserted_at, %State{} = state) do
    accumulated_tokens = tokens + (now - last_inserted_at) / state.interval * state.refill

    if accumulated_tokens > state.max_accumulated do
      state.max_accumulated
    else
      accumulated_tokens
    end
  end
end
