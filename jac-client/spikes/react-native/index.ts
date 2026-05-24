// Spike entry point. Mirrors the shape that R2's future `native_entry.jac`
// will emit: `AppRegistry.registerComponent(name, () => RootComponent)`.
import { registerRootComponent } from 'expo';
import App from './App';

registerRootComponent(App);
