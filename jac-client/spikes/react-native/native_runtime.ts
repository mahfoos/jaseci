/**
 * Spike-only native runtime that satisfies the `@jac/runtime` import surface
 * produced by the Jac->JS compiler. Mirrors the web exports from
 * `jac-client/jac_client/plugin/client_runtime.cl.jac` but only the slice
 * needed for the basic-app fixture is actually implemented. Everything else
 * is a loud stub so unsupported paths fail fast rather than silently.
 *
 * This file is intentionally hand-written. The production runtime will be
 * generated from `client_runtime_native.cl.jac` after refactor R3 lands.
 */
import * as React from 'react';
import {
  View,
  Text,
  Pressable,
  TextInput,
  Image,
  Linking,
  StyleSheet,
} from 'react-native';
import Constants from 'expo-constants';
import * as SecureStore from 'expo-secure-store';
import {
  ErrorBoundary as ReactErrorBoundary,
  FallbackProps,
} from 'react-error-boundary';

// ---------------------------------------------------------------------------
// Tag map (D10 in REACT_NATIVE_ARCHITECTURE.md)
// ---------------------------------------------------------------------------

const VIEW_TAGS = new Set([
  'div', 'section', 'main', 'article', 'header', 'footer', 'nav', 'aside',
  'ul', 'ol', 'li', 'form',
]);
const TEXT_TAGS = new Set([
  'span', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'label', 'strong', 'em', 'small',
]);

const warned = new Set<string>();
function warnOnce(tag: string) {
  if (warned.has(tag)) return;
  warned.add(tag);
  // eslint-disable-next-line no-console
  console.warn(
    `[jac-native-runtime] Unmapped HTML tag <${tag}>. Rendering as <View> ` +
      `with a debug border. Replace with a React Native primitive or add to ` +
      `the tag map.`,
  );
}

const debugStyles = StyleSheet.create({
  unmapped: {
    borderWidth: 1,
    borderColor: 'red',
    borderStyle: 'dashed',
  },
});

/**
 * Best-effort filter of web-only DOM props that React Native warns about.
 * The compiled Jac bundle emits HTML attribute names verbatim (`class`,
 * `data-id`, `onClick`, etc.). We translate the few that have direct RN
 * analogues and drop the rest with a console.debug.
 */
function adaptProps(tag: string, props: Record<string, unknown> | null | undefined): Record<string, unknown> {
  if (!props) return {};
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(props)) {
    const value = props[key];
    if (value === undefined || value === null) continue;
    switch (key) {
      case 'class':
      case 'className':
        // RN has no className. Preserve for debugging via accessibilityLabel.
        out.accessibilityLabel = String(value);
        break;
      case 'style':
        out.style = value;
        break;
      case 'onClick':
        out.onPress = value;
        break;
      case 'onChange':
        out.onChangeText = value;
        break;
      case 'value':
      case 'placeholder':
      case 'editable':
      case 'multiline':
      case 'secureTextEntry':
        out[key] = value;
        break;
      case 'key':
      case 'ref':
        out[key] = value;
        break;
      default:
        if (key.startsWith('data-') || key.startsWith('aria-')) {
          // Drop silently; not meaningful on native.
          break;
        }
        // Pass through anything that looks like an RN prop already.
        out[key] = value;
    }
  }
  return out;
}

type AnyChildren = React.ReactNode | React.ReactNode[];

function flattenChildren(children: AnyChildren): React.ReactNode[] {
  if (children === undefined || children === null) return [];
  const arr = Array.isArray(children) ? children : [children];
  return arr.filter((c) => c !== null && c !== undefined);
}

function wrapTextChildren(children: React.ReactNode[]): React.ReactNode[] {
  // Text-tag children may be raw strings/numbers — RN requires those inside
  // <Text>. We're already rendering <Text>, so passthrough is fine.
  return children;
}

function makeButton(
  props: Record<string, unknown>,
  children: React.ReactNode[],
): React.ReactElement {
  return React.createElement(
    Pressable,
    props,
    React.createElement(Text, null, ...children),
  );
}

function makeLink(
  props: Record<string, unknown>,
  children: React.ReactNode[],
): React.ReactElement {
  const href = (props as { href?: string }).href;
  const onPress = href
    ? () => {
        Linking.openURL(href).catch((e) => console.warn('Linking.openURL failed', e));
      }
    : (props as { onPress?: () => void }).onPress;
  const { href: _ignored, ...rest } = props as Record<string, unknown>;
  return React.createElement(
    Text,
    { ...rest, onPress },
    ...children,
  );
}

/**
 * The whole point of the spike: dispatch HTML-style tags emitted by the Jac
 * compiler into React Native primitives without modifying the bundle.
 */
export function __jacJsx(
  tag: unknown,
  props?: Record<string, unknown> | null,
  children?: AnyChildren,
): React.ReactElement | null {
  const kidArray = flattenChildren(children);

  if (tag === null || tag === undefined) {
    return React.createElement(React.Fragment, null, ...kidArray);
  }

  // Component reference (React function/class) — pass through.
  if (typeof tag !== 'string') {
    return React.createElement(tag as React.ElementType, (props ?? {}) as object, ...kidArray);
  }

  const adapted = adaptProps(tag, props ?? {});

  if (VIEW_TAGS.has(tag)) {
    return React.createElement(View, adapted, ...kidArray);
  }
  if (TEXT_TAGS.has(tag)) {
    return React.createElement(Text, adapted, ...wrapTextChildren(kidArray));
  }
  if (tag === 'button') {
    return makeButton(adapted, kidArray);
  }
  if (tag === 'input' || tag === 'textarea') {
    if (tag === 'textarea') (adapted as { multiline?: boolean }).multiline = true;
    return React.createElement(TextInput, adapted);
  }
  if (tag === 'img') {
    return React.createElement(Image, adapted);
  }
  if (tag === 'a') {
    return makeLink(adapted, kidArray);
  }

  warnOnce(tag);
  const debugProps = __DEV__
    ? { ...adapted, style: [debugStyles.unmapped, (adapted as { style?: unknown }).style] }
    : adapted;
  return React.createElement(View, debugProps, ...kidArray);
}

// ---------------------------------------------------------------------------
// Walker / function fetch — minimum viable
// ---------------------------------------------------------------------------

export function __getApiBaseUrl(): string {
  const extra =
    (Constants.expoConfig?.extra as { apiBaseUrl?: string } | undefined) ?? {};
  // 10.0.2.2 is the Android emulator's loopback to the host machine.
  return extra.apiBaseUrl ?? 'http://10.0.2.2:8000';
}

async function doWalkerFetch(
  walker: string,
  nodeId: string,
  fields: Record<string, unknown>,
): Promise<unknown> {
  const token = await __getLocalStorage('jac_token');
  const base = __getApiBaseUrl();
  const url = nodeId
    ? `${base}/walker/${walker}/${nodeId}`
    : `${base}/walker/${walker}`;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(fields ?? {}),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Walker ${walker} failed (${response.status}): ${text}`);
  }
  const payload = (await response.json()) as { data?: unknown };
  return payload?.data ?? {};
}

export async function __jacSpawn(
  left: string,
  right: string = '',
  fields: Record<string, unknown> = {},
): Promise<unknown> {
  return doWalkerFetch(left, right, fields);
}

export function jacSpawn(
  left: string,
  right: string = '',
  fields: Record<string, unknown> = {},
): Promise<unknown> {
  return __jacSpawn(left, right, fields);
}

export async function __jacCallFunction(
  functionName: string,
  args: Record<string, unknown> = {},
): Promise<unknown> {
  const token = await __getLocalStorage('jac_token');
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`${__getApiBaseUrl()}/function/${functionName}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(args),
  });
  if (!response.ok) {
    throw new Error(`Function ${functionName} failed (${response.status})`);
  }
  return response.json();
}

// ---------------------------------------------------------------------------
// Storage adapter — expo-secure-store (D8)
// ---------------------------------------------------------------------------

/**
 * Note: SecureStore is async-only, but the Jac runtime exposes these as
 * synchronous on the web (localStorage). We expose async variants here and
 * accept that the spike's compiled bundle will await them. The real
 * production runtime will need to either (a) cache hot keys in memory or
 * (b) change the runtime contract to async on both platforms.
 */
export async function __getLocalStorage(key: string): Promise<string | null> {
  try {
    return await SecureStore.getItemAsync(key);
  } catch (e) {
    console.warn('SecureStore.getItemAsync failed', e);
    return null;
  }
}

export async function __setLocalStorage(key: string, value: string): Promise<void> {
  try {
    await SecureStore.setItemAsync(key, value);
  } catch (e) {
    console.warn('SecureStore.setItemAsync failed', e);
  }
}

export async function __removeLocalStorage(key: string): Promise<void> {
  try {
    await SecureStore.deleteItemAsync(key);
  } catch (e) {
    console.warn('SecureStore.deleteItemAsync failed', e);
  }
}

// ---------------------------------------------------------------------------
// React hook re-exports
// ---------------------------------------------------------------------------

export const useState = React.useState;
export const useEffect = React.useEffect;

// ---------------------------------------------------------------------------
// Error boundary surface
// ---------------------------------------------------------------------------

export const JacClientErrorBoundary = ReactErrorBoundary;

export function ErrorFallback({ error, resetErrorBoundary }: FallbackProps) {
  return React.createElement(
    View,
    { style: { padding: 16 } },
    React.createElement(Text, { style: { fontWeight: 'bold', color: 'red' } }, 'Something broke'),
    React.createElement(Text, null, String(error?.message ?? error)),
    React.createElement(
      Pressable,
      { onPress: resetErrorBoundary, style: { marginTop: 12 } },
      React.createElement(Text, null, 'Retry'),
    ),
  );
}

export function __jacInstallErrorHandlers(): void {
  // No-op in spike. RN LogBox already surfaces unhandled errors in dev.
}

export function __jacReactErrorHandler(error: unknown, info: unknown): void {
  console.warn('[jac] React error', error, info);
}

export async function __jacReportError(
  message: string,
  stack: string = '',
): Promise<void> {
  console.warn('[jac] reportError', message, stack);
}

// ---------------------------------------------------------------------------
// Loud stubs — exported so the bundle can import them, but throw if invoked.
// ---------------------------------------------------------------------------

function stub(name: string): never {
  throw new Error(
    `[jac-native-runtime] ${name} is not implemented in the Phase 0 spike. ` +
      `See REACT_NATIVE_ARCHITECTURE.md.`,
  );
}

export const Router = (() => stub('Router')) as unknown;
export const Routes = (() => stub('Routes')) as unknown;
export const Route = (() => stub('Route')) as unknown;
export const Link = (() => stub('Link')) as unknown;
export const Navigate = (() => stub('Navigate')) as unknown;
export const Outlet = (() => stub('Outlet')) as unknown;
export const useNavigate = () => stub('useNavigate');
export const useLocation = () => stub('useLocation');
export const useParams = () => stub('useParams');
export const useRouter = () => stub('useRouter');
export const navigate = (_path: string) => stub('navigate');

export const JacSchema = new Proxy(function () {}, {
  get: () => () => stub('JacSchema.*'),
  apply: () => stub('JacSchema()'),
}) as unknown;

export function jacSignup(): never { return stub('jacSignup'); }
export function jacLogin(): never { return stub('jacLogin'); }
export function jacLogout(): never { return stub('jacLogout'); }
export function jacIsLoggedIn(): boolean { return false; }
export function AuthGuard(): never { return stub('AuthGuard'); }
export function JacAwaiting(): never { return stub('JacAwaiting'); }
export function errorOverlay(): never { return stub('errorOverlay'); }
export function useJacForm(): never { return stub('useJacForm'); }
export function JacForm(): never { return stub('JacForm'); }

// Cache internals — return inert values; the spike calls walkers directly
// via doWalkerFetch and bypasses the cache layer.
export function __getEndpointEffects(): Record<string, unknown> { return {}; }
export function __getCacheState(): Record<string, unknown> { return {}; }
export function __isFresh(): boolean { return false; }
export function __cacheGet(): Record<string, unknown> { return {}; }
export function __cacheSet(): void { /* no-op */ }
export function __evictOldest(): void { /* no-op */ }
export function __invalidateEndpoint(): void { /* no-op */ }
export function __overlaps(): boolean { return false; }
export async function __doWalkerFetch(
  walker: string,
  nodeId: string,
  fields: Record<string, unknown>,
): Promise<unknown> {
  return doWalkerFetch(walker, nodeId, fields);
}
export async function __doFuncFetch(
  functionName: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  return __jacCallFunction(functionName, args);
}
export async function __cachedEndpointCall<T>(
  _endpointKey: string,
  _argsKey: string,
  fetchFn: () => Promise<T>,
): Promise<T> {
  return fetchFn();
}

export function __normalizeIdentity(x: unknown): Record<string, unknown> {
  if (x && typeof x === 'object') return x as Record<string, unknown>;
  return { type: 'username', value: x };
}
export function __normalizeCredential(x: unknown): Record<string, unknown> {
  if (x && typeof x === 'object') return x as Record<string, unknown>;
  return { type: 'password', password: x };
}
