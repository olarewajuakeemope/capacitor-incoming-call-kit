import type { PluginListenerHandle} from '@capacitor/core';
import { WebPlugin } from '@capacitor/core';

import type { Events, FlutterCallkitIncomingPlugin, MethodNames, Responses } from './definitions';

export class FlutterCallkitIncomingWeb extends WebPlugin implements FlutterCallkitIncomingPlugin {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async onMethod(_options: {
    methodName: MethodNames
    options?: string
  }): Promise<Responses> {
    throw new Error('Web platform is not supported.')
  }
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async addListener(_event: Events, _cb: (data: any) => void): Promise<PluginListenerHandle> {
    throw new Error('Web platform is not supported.')
  }
}
