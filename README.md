# Leaky

Implements a token-based rate limiter using the leaky bucket algorithm, ideal for controlling access rates to resources in Elixir applications.
This implementation leverages ETS for optimized performance, making it suitable for high-load environments.

## Overview

The leaky bucket algorithm helps smooth out bursty traffic by limiting the rate at which actions are taken.
It's like a bucket with a hole: tokens, representing permissions to take an action, drip out at a constant rate.
If the bucket is full, new actions must wait, ensuring the overall rate does not exceed the desired threshold.
Read more about the algorithm here: https://en.wikipedia.org/wiki/Leaky_bucket

## Instalation

Add the following to your `mix.exs` file:
```elixir
  def deps do
  [
    {:leaky, "~> 0.1.1"},
  ]
end
```
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

