/**
 * Phase 0 spike screen.
 *
 * Top half: the compiled `app` export from `jac-compiled/main.js` rendered
 * unmodified — this proves the tag map in native_runtime.ts handles the
 * basic-app fixture's <div>/<h1>/<button> shape.
 *
 * Bottom half: a hand-written button that calls `jacSpawn('ping')` against
 * the local `jac start` backend in ./backend, validating the
 * compiled-bundle -> runtime -> fetch round-trip.
 */
import React, { useCallback, useState } from 'react';
import {
  SafeAreaView,
  ScrollView,
  View,
  Text,
  Pressable,
  StyleSheet,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { JacClientErrorBoundary, ErrorFallback, jacSpawn } from './native_runtime';

// @ts-expect-error - The compiled JS has no type declarations.
import { app as JacApp } from './jac-compiled/main.js';

type PingResult =
  | { kind: 'idle' }
  | { kind: 'pending' }
  | { kind: 'ok'; payload: unknown }
  | { kind: 'err'; message: string };

function PingPanel() {
  const [result, setResult] = useState<PingResult>({ kind: 'idle' });
  const onPress = useCallback(async () => {
    setResult({ kind: 'pending' });
    try {
      const payload = await jacSpawn('ping');
      setResult({ kind: 'ok', payload });
    } catch (e) {
      setResult({ kind: 'err', message: e instanceof Error ? e.message : String(e) });
    }
  }, []);

  return (
    <View style={styles.panel}>
      <Text style={styles.heading}>Backend round-trip</Text>
      <Pressable style={styles.button} onPress={onPress}>
        <Text style={styles.buttonText}>Call ping</Text>
      </Pressable>
      <Text style={styles.resultLabel}>Result:</Text>
      <Text style={styles.result}>
        {result.kind === 'idle' && 'Tap above to call the walker.'}
        {result.kind === 'pending' && 'Calling...'}
        {result.kind === 'ok' && JSON.stringify(result.payload, null, 2)}
        {result.kind === 'err' && `Error: ${result.message}`}
      </Text>
    </View>
  );
}

export default function App() {
  return (
    <JacClientErrorBoundary FallbackComponent={ErrorFallback}>
      <SafeAreaView style={styles.root}>
        <StatusBar style="auto" />
        <ScrollView contentContainerStyle={styles.content}>
          <Text style={styles.sectionLabel}>Jac-compiled UI:</Text>
          <View style={styles.jacBox}>
            <JacApp />
          </View>
          <PingPanel />
        </ScrollView>
      </SafeAreaView>
    </JacClientErrorBoundary>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 16 },
  sectionLabel: { fontSize: 12, opacity: 0.6 },
  jacBox: {
    padding: 12,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
  },
  panel: {
    padding: 12,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    gap: 8,
  },
  heading: { fontSize: 16, fontWeight: 'bold' },
  button: {
    backgroundColor: '#2563eb',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 6,
    alignSelf: 'flex-start',
  },
  buttonText: { color: 'white', fontWeight: '600' },
  resultLabel: { fontSize: 12, opacity: 0.6, marginTop: 8 },
  result: { fontFamily: 'monospace' },
});
