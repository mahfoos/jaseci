// // jac-client: scaffold-managed; remove this line to opt out of auto-refresh
import React from 'react';
import { SafeAreaView, StatusBar } from 'react-native';
import {
  JacClientErrorBoundary,
  ErrorFallback,
  __jacReactErrorHandler,
  __jacInstallErrorHandlers,
// @ts-expect-error - Jac runtime has no .d.ts yet
} from '@jac/runtime';
// @ts-expect-error - Jac compiled bundle has no .d.ts.
import { app as JacApp } from '../jac-app';

__jacInstallErrorHandlers();

export default function App() {
  return (
    <JacClientErrorBoundary
      FallbackComponent={ErrorFallback}
      onError={__jacReactErrorHandler}
    >
      <SafeAreaView style={{ flex: 1 }}>
        <StatusBar />
        <JacApp />
      </SafeAreaView>
    </JacClientErrorBoundary>
  );
}
