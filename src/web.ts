import { WebPlugin } from '@capacitor/core';

import type { FlutterCallkitIncomingPluginPlugin } from './definitions';

export class FlutterCallkitIncomingPluginWeb extends WebPlugin implements FlutterCallkitIncomingPluginPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
