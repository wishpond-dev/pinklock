defmodule Pinklock do
  @moduledoc """
  Not-quite a redlock, but close enough for what we're using it for and built on
  sentinel.
  """

  # In seconds, since that is the resolution that we get from redis.
  @default_ttl 60

  @doc """
  This should really be private but I want to be able to test it directly so...
  just don't use it, plskthx.

  Alternatively I should extract it to something simple that can be used
  anywhere.
  """
  @spec with_lock(pid() | atom(), String.t(), function(), keyword()) :: :ok
  def with_lock(sentinel, lock_key, handler, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    # Generate a timestamp after which it will expire.
    #
    # One minute from now is ample.
    expiry = :os.system_time(:millisecond) + ttl * 10_000

    # We don't need a full-fat redlock for something this minor.
    {:ok, res} =
      RedixSentinel.command(
        sentinel,
        ["SETNX", lock_key, expiry]
      )

    case res do
      1 ->
        {:ok, _res} =
          RedixSentinel.command(
            sentinel,
            ["EXPIRE", lock_key, ttl]
          )

        # Now that we have a lock, start work.
        handler.()

        # Finally, clean up the lock.
        RedixSentinel.command(sentinel, ["DEL", lock_key])

      0 ->
        # We do not have the lock. Check to see if the current lock has gone
        # stale. Given that we already put the redis expiry on the lock field
        # this case is only here to recover from the very specific and very rare
        # situation in which we've created the lock and then lost the connection
        # before setting the expiry.
        {:ok, res} =
          RedixSentinel.command(
            sentinel,
            ["GET", lock_key]
          )

        saved_expiry = String.to_integer(res)

        if saved_expiry < :os.system_time(:millisecond) do
          RedixSentinel.command(
            sentinel,
            ["DEL", lock_key]
          )

          # Now run again with the same params
          with_lock(sentinel, lock_key, handler)
        end
    end
  end
end
