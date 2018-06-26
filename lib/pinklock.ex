defmodule Pinklock do
  @moduledoc """
  Not-quite a redlock, but close enough for what we're using it for and built on
  sentinel.
  """

  # In seconds, since that is the resolution that we get from redis.
  @default_ttl 60

  @doc """
  Get a basic redis lock.

      iex> Pinklock.with_lock(:sentinel, "lock_key", fn msg -> msg end)

  Defaults to using RedixSentinel for commands but can be convinced to use Redix
  instead by passing it in as the client:

      iex> Pinklock.with_lock({Redix, pid}, "lock_key", fn msg -> msg end)

  """

  def with_lock(client, lock_key, handler, opts \\ [])

  @spec with_lock({module(), pid() | atom()}, String.t(), function(), keyword()) :: :ok
  def with_lock({client, pid}, lock_key, handler, opts) do
    with_lock(pid, lock_key, handler, opts ++ [client: client])
  end

  @spec with_lock(pid() | atom(), String.t(), function(), keyword()) :: :ok
  def with_lock(pid, lock_key, handler, opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    client = Keyword.get(opts, :client, RedixSentinel)

    # Generate a timestamp after which it will expire.
    #
    # One minute from now is ample.
    expiry = :os.system_time(:millisecond) + ttl * 10_000

    # We don't need a full-fat redlock for something this minor.
    {:ok, res} = apply(client, :command, [pid, ["SETNX", lock_key, expiry]])

    case res do
      1 ->
        {:ok, _res} = apply(client, :command, [pid, ["EXPIRE", lock_key, ttl]])

        # Now that we have a lock, start work.
        handler.()

        # Finally, clean up the lock.
        client.command(pid, ["DEL", lock_key])

      0 ->
        # We do not have the lock. Check to see if the current lock has gone
        # stale. Given that we already put the redis expiry on the lock field
        # this case is only here to recover from the very specific and very rare
        # situation in which we've created the lock and then lost the connection
        # before setting the expiry.
        {:ok, res} = apply(client, :command, [pid, ["GET", lock_key]])

        saved_expiry = String.to_integer(res)

        if saved_expiry < :os.system_time(:millisecond) do
          apply(client, :command, [pid, ["DEL", lock_key]])

          # Now run again with the same params
          with_lock(pid, lock_key, handler)
        end
    end
  end
end
