ExUnit.start()

defmodule Redis do
  def start_link do
    RedixSentinel.start_link(Application.get_env(:pinklock, :redis), [database: 0], [])
  end
end

defmodule PinklockConsumer do
  def start_link(sentinel, lock_key, opts \\ []) do
    GenServer.start_link(__MODULE__, {sentinel, lock_key, opts})
  end

  def init({sentinel, lock_key, opts}) do
    {:ok,
     %{
       sentinel: sentinel,
       lock_key: lock_key,
       opts: opts
     }}
  end

  def handle_info({:lock, handler}, %{sentinel: sentinel, lock_key: lock_key, opts: opts} = state) do
    Pinklock.with_lock(sentinel, lock_key, handler, opts)
    {:noreply, state}
  end
end
