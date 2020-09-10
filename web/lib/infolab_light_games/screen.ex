defmodule Screen do
  use GenServer

  alias Phoenix.PubSub

  @dims Application.get_env(:infolab_light_games, Screen)[:dims]

  @blank Matrix.of_dims(elem(@dims, 0), elem(@dims, 1), Pixel.empty())

  def dims do
    @dims
  end

  def centre_pos do
    {x, y} = @dims

    {Integer.floor_div(x, 2), Integer.floor_div(y, 2)}
  end

  def blank do
    @blank
  end

  @impl true
  def init(_opts) do
    z = :zlib.open()

    {:ok, {@blank, z}}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, @dims, name: __MODULE__)
  end

  @impl true
  def handle_call(:latest, _from, {frame, _} = state) do
    {:reply, frame, state}
  end

  @impl true
  def handle_call(:full_as_diff, _from, {frame, z} = state) do
    v = Matrix.reduce(frame, [], fn x, y, pix, acc ->
      [%{x: x, y: y, new: pix} | acc]
    end)
    d = compress_b64_json(v, z)

    {:reply, d, state}
  end

  @impl true
  def handle_cast({:update_frame, frame}, {old_frame, z}) do
    diff = Matrix.diff(old_frame, frame)

    if not Enum.empty?(diff) do
      d = compress_b64_json(diff, z)
      PubSub.broadcast(InfolabLightGames.PubSub, "screen:diff", {:screen_diff, d})
    end

    PubSub.broadcast(InfolabLightGames.PubSub, "screen:full", {:screen_full, frame})
    {:noreply, {frame, z}}
  end

  defp compress_b64_json(val, z) do
    :ok = :zlib.deflateInit(z)
    d = :zlib.deflate(z, Jason.encode_to_iodata!(val), :finish)
    :zlib.deflateEnd(z)
    Base.encode64(IO.iodata_to_binary(d))
  end

  def update_frame(new_frame) do
    GenServer.cast(__MODULE__, {:update_frame, new_frame})
  end

  def full_as_diff do
    GenServer.call(__MODULE__, :full_as_diff)
  end

  def latest do
    GenServer.call(__MODULE__, :latest)
  end
end
