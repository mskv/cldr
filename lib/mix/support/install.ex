defmodule Cldr.Install do
  @moduledoc """
  Support for installing locales on demand.

  When installed as a package on from [hex](http://hex.pm), `Cldr` has only
  the default locale, "en", installed and configured.

  When other locales are added to the configuration `Cldr` will attempt to
  download the locale from [github](https://github.com/kipcole9/cldr)
  during compilation.

  If `Cldr` is installed from github directly then all locales are already
  installed.
  """

  @doc """
  Install all the configured locales.
  """
  def install_known_locales do
    ensure_client_dirs_exist!(client_locale_dir())
    Enum.each Cldr.known_locales(), &install_locale/1
    :ok
  end

  @doc """
  Install all available locales.
  """
  def install_all_locales do
    ensure_client_dirs_exist!(client_locale_dir())
    Enum.each Cldr.all_locales(), &install_locale/1
    :ok
  end

  @doc """
  Download the requested locale from github into the
  client app data directory.

  The data directory is typically `./priv/cldr/locales`.

  This function is intended to be invoked during application
  compilation when a valid locale is configured but is not yet
  installed in the application.

  An http request to the master github repository for `Cldr` is made
  to download the correct version of the locale file which is then
  written to the configured data directory.
  """
  def install_locale(locale, options \\ []) do
    if !locale_installed?(locale) or options[:force] do
      Application.ensure_started(:inets)
      Application.ensure_started(:ssl)
      do_install_locale(locale, locale in Cldr.all_locales())
    end
  end

  def do_install_locale(locale, false) do
    raise Cldr.UnknownLocaleError,
      "Requested locale #{inspect locale} is not known."
  end

  def do_install_locale(locale, true) do
    IO.write "Downloading and installing locale #{inspect locale} ... "
    locale_file_name = "#{locale}.json"
    url = "#{base_url()}#{locale_file_name}" |> String.to_charlist

    case :httpc.request(url) do
      {:ok, {{_version, 200, 'OK'}, _headers, body}} ->
        output_file_name = "#{client_locale_dir()}/#{locale_file_name}"
        File.write!(output_file_name, :erlang.list_to_binary(body))
        IO.puts "done."

      {_, {{_version, code, message}, _headers, _body}} ->
        IO.puts "error!"
        raise RuntimeError,
          message: "Couldn't download locale #{inspect locale}. " <>
            "HTTP Error: (#{code}) #{inspect message}\nURL: #{inspect url}"
    end
  end

  @doc """
  Builds the base url to retrieve a locale file from github.

  The url is build using the version number of the `Cldr` application.
  If the version is a `-dev` version then the locale file is downloaded
  from the master branch.
  """
  @base_url "https://raw.githubusercontent.com/kipcole9/cldr/"
  def base_url do
    version = Cldr.Mixfile.project[:version]
    branch = if String.contains?(version, "-dev"), do: "master", else: version
    @base_url <> branch <> "/priv/cldr/locales/"
  end

  @doc """
  Returns a `boolean` indicating if the requested locale is installed.

  No checking of the validity of the `locale` itself is performed.  The
  check is based upon whether there is a locale file installed in the
  client application or in `Cldr` itself.
  """
  def locale_installed?(locale) do
    !!Cldr.Config.locale_path(locale)
  end

  @doc """
  Returns the directory where the client app stores `Cldr` data
  """
  def client_data_dir do
    Cldr.Config.data_dir()
  end

  @doc """
  Returns the directory into which locale files are stored
  for a client application.

  The directory is relative to the configured data directory for
  a client application.  That is typically `./priv/cldr`
  so that locales typically get stored in `./priv/cldr/locales`.
  """
  def client_locale_dir do
    "#{client_data_dir()}/locales"
  end

  def client_locale_file(locale) do
    Path.join(client_locale_dir(), "#{locale}.json")
  end

  @doc """
  Returns the directory where `Cldr` stores the core CLDR data
  """
  def cldr_data_dir do
    Path.join(Cldr.Config.cldr_home(), "/priv/cldr")
  end

  @doc """
  Returns the directory where `Cldr` stores locales that can be
  used in a client app.

  Current strategy is to only package the "en" locale in `Cldr`
  itself and that any other locales are downloaded when configured
  and the client app is compiled with `Cldr` as a `dep`.
  """
  def cldr_locale_dir do
    Path.join(cldr_data_dir(), "/locales")
  end

  @doc """
  Returns the path of the consolidated locale file stored in the `Cldr`
  package (not the client application).

  Since these consolidated files go in the github repo we consoldiate
  them into the `Cldr` data directory which is
  `Cldr.Config.cldr_home() <> /priv/cldr/locales`.
  """
  def consolidated_locale_file(locale) do
    Path.join(cldr_locale_dir(), "#{locale}.json")
  end

  # Create the client app locales directory and any directories
  # that don't exist above it.
  defp ensure_client_dirs_exist!(dir) do
    paths = String.split(dir, "/")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&(String.replace_prefix(&1, "", "/")))
    do_ensure_client_dirs(paths)
  end

  defp do_ensure_client_dirs([h | []]) do
    create_dir(h)
  end

  defp do_ensure_client_dirs([h | t]) do
    create_dir(h)
    do_ensure_client_dirs([h <> hd(t) | tl(t)])
  end

  defp create_dir(dir) do
    case File.mkdir(dir) do
      :ok ->
        :ok
      {:error, :eexist} ->
        :ok
      {:error, :eisdir} ->
        :ok
      {:error, code} ->
        raise RuntimeError,
          message: "Couldn't create #{dir}: #{inspect code}"
    end
  end
end