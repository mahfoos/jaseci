// // jac-client: scaffold-managed; remove this line to opt out of auto-refresh
import React from 'react';
import { View, Text } from 'react-native';

export const app = () =>
  React.createElement(
    View,
    { style: { padding: 24 } },
    React.createElement(
      Text,
      null,
      'Run `jac build --client react-native` to compile the Jac app.'
    )
  );
