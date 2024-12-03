import { registerPlugin } from '@capacitor/core';

import type { FlutterCallkitIncomingPluginPlugin } from './definitions';

const FlutterCallkitIncomingPlugin = registerPlugin<FlutterCallkitIncomingPluginPlugin>('FlutterCallkitIncomingPlugin', {
  web: () => import('./web').then((m) => new m.FlutterCallkitIncomingPluginWeb()),
});

export * from './definitions';
export { FlutterCallkitIncomingPlugin };
