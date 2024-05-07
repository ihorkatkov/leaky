defmodule Leaky.MixProject do
  use Mix.Project

  def project do
    [
      app: :leaky,
      version: "0.1.1",
      elixir: "~> 1.15",
      name: "Leaky",
      source_url: "https://github.com/ihorkatkov/leaky",
      description: description(),
      package: package(),
      docs: [
        main: "Leaky",
        extras: ["README.md"]
      ],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:styler, "~> 0.11.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Implements a token-based rate limiter using the leaky bucket algorithm, ideal for controlling access rates to resources in Elixir applications. This implementation leverages ETS for optimized performance, making it suitable for high-load environments."
  end

  defp package do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "leaky",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/ihorkatkov/leaky"}
    ]
  end
end
