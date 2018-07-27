defmodule PinklockTest do
  use ExUnit.Case, async: false

  describe "with_lock/3" do
    @lock_key "test_lock_key"

    @tag :integration
    test "it should get the lock and set expiry, run the callback, then clean the lock up" do
      {:ok, sentinel} = Sentinel.start_link()
      pid = self()

      # If the lock exist that will mess with our test so delete it now.
      RedixSentinel.command(sentinel, ["DEL", @lock_key])

      # A couple of lock threads to simulate many workers
      {:ok, lock_1} = PinklockConsumer.start_link(sentinel, @lock_key)
      {:ok, lock_2} = PinklockConsumer.start_link(sentinel, @lock_key)

      # Send a message to the lock
      send(lock_1, {:lock,
       fn ->
         # Sleep, to allow the second write attempt to run while the lock is
         # still held.
         :timer.sleep(50)
         send(pid, {:lock_run})
         :ok
       end})

      # Sleep a little bit to make sure the first lock is grabbed.
      :timer.sleep(25)

      # Attempt to get the lock in a second process. This one shouldn't get
      # fired because the lock exists.
      send(
        lock_2,
        {:lock,
         fn ->
           send(pid, {:not_run})
           :ok
         end}
      )

      # Sleep, waiting for the process to finish.
      assert_receive {:lock_run}, 100
      refute_receive {:not_run}, 100

      # Now sleep a moment, to let the thread clean itself up.
      :timer.sleep(60)

      # And check that it's been cleaned up by running another job.
      send(
        lock_1,
        {:lock,
         fn ->
           send(pid, {:run_again})
           :ok
         end}
      )

      # Final check
      assert_receive {:run_again}, 10
    end

    @tag :integration
    test "it should not clean up a non-expired lock without an expiry" do
      {:ok, sentinel} = Sentinel.start_link()
      pid = self()

      # If the lock exist that will mess with our test so delete it now.
      RedixSentinel.command(sentinel, ["DEL", @lock_key])

      # Now create a non-expired lock but don't set an expiry on it.
      RedixSentinel.command(sentinel, ["SET", @lock_key, :os.system_time(:millisecond) + 10_000])

      # Attempt and fail to get the lock.
      Pinklock.with_lock(sentinel, @lock_key, fn ->
        send(pid, {:not_run})
      end)

      refute_received {:not_run}
    end

    @tag :integration
    test "it should clean up an expired lock without an expiry" do
      {:ok, sentinel} = Sentinel.start_link()
      pid = self()

      # If the lock exist that will mess with our test so delete it now.
      RedixSentinel.command(sentinel, ["DEL", @lock_key])

      # Now create a non-expired lock but don't set an expiry on it.
      RedixSentinel.command(sentinel, ["SET", @lock_key, :os.system_time(:millisecond) - 10_000])

      # Attempt and fail to get the lock.
      Pinklock.with_lock({RedixSentinel, sentinel}, @lock_key, fn ->
        send(pid, {:run})
      end)

      assert_received {:run}
    end

    @tag :integration
    test "it should work with redix as well" do
      {:ok, redis} = Redis.start_link()
      pid = self()

      # If the lock exist that will mess with our test so delete it now.
      Redix.command(redis, ["DEL", @lock_key])

      # Attempt and fail to get the lock.
      Pinklock.with_lock({Redix, redis}, @lock_key, fn ->
        send(pid, {:run})
      end)

      assert_received {:run}
    end
  end
end
