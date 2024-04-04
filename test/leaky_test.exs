defmodule LeakyTest do
  use ExUnit.Case, async: true

  @bucket :bucket
  @cost 1

  setup do
    configuration = [max_accumulated: 4, refill: 1, interval: 10, bucket_name: @bucket]
    start_supervised!({Leaky, configuration})

    :ok
  end

  describe "acquire/3" do
    test "check rate" do
      assert {:allow, 3} == Leaky.acquire(@bucket, @cost)
      assert {:allow, 2} == Leaky.acquire(@bucket, @cost)
      assert {:allow, 1} == Leaky.acquire(@bucket, @cost)
      assert {:allow, 0} == Leaky.acquire(@bucket, @cost)

      assert :deny = Leaky.acquire(@bucket, @cost)

      # by this time, has recovered 1 token (refill: 1, interval: 10)
      :timer.sleep(10)
      assert {:allow, _} = Leaky.acquire(@bucket, @cost)
      assert :deny = Leaky.acquire(@bucket, @cost)
    end
  end

  describe "inspect/2" do
    test "returns amount of available tokens" do
      assert {:allow, 3} == Leaky.acquire(@bucket, @cost)

      assert 3 == Leaky.inspect(@bucket)
    end
  end

  describe "adjust_tokens/2" do
    test "increments available tokens bypassing the rate check" do
      assert {:allow, 2} == Leaky.acquire(@bucket, 2)
      assert :ok = Leaky.adjust_tokens(@bucket, 2)

      :timer.sleep(2)

      assert 4 == Leaky.inspect(@bucket)
    end

    test "decrements available tokens bypassing the rate check" do
      assert :ok = Leaky.adjust_tokens(@bucket, -2)

      :timer.sleep(2)

      assert 2 == Leaky.inspect(@bucket)
    end
  end

  describe "update_configuration/2" do
    test "updates configuration in a running process" do
      Leaky.update_configuration(max_accumulated: 10, refill: 2, interval: 5)

      assert %Leaky.State{max_accumulated: 10, refill: 2, interval: 5} = :sys.get_state(Process.whereis(Leaky))
    end
  end

  describe "naming options" do
    test "works with {:via, _, _} name" do
      start_supervised!({Registry, [name: Leaky.Registry, keys: :unique]})
      name = {:via, Registry, {Leaky.Registry, "name"}}

      configuration = [
        bucket_name: :new_bucket,
        max_accumulated: 4,
        refill: 1,
        interval: 10,
        name: name
      ]

      start_supervised!({Leaky, configuration}, id: make_ref())

      assert {:allow, 3} == Leaky.acquire(@bucket, @cost, name)
    end

    test "works with {:global, _} name" do
      name = {:global, {Leaky, "name"}}

      configuration = [
        bucket_name: :new_bucket,
        max_accumulated: 4,
        refill: 1,
        interval: 10,
        name: name
      ]

      start_supervised!({Leaky, configuration}, id: make_ref())

      assert {:allow, 3} == Leaky.acquire(@bucket, @cost, name)
    end
  end
end
