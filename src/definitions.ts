export interface FlutterCallkitIncomingPluginPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
