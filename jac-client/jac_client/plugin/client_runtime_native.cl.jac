"""React Native client runtime (D9 — imports core, adds RN adapters)."""

import from 'react' { * as React }
import from 'react' { useState as reactUseState, useEffect as reactUseEffect }
import from 'react-native' {
    View as RNView,
    Text as RNText,
    Pressable as RNPressable,
    TextInput as RNTextInput,
    Image as RNImage,
    Linking as RNLinking
}
import from '@react-navigation/native' {
    NavigationContainer as JacNavigationContainer,
    CommonActions as JacCommonActions,
    useNavigation as jacUseNavigation,
    useRoute as jacUseRoute
}
import from '@react-navigation/native-stack' {
    createNativeStackNavigator as jacCreateNativeStackNavigator
}
import from 'expo-secure-store' { * as SecureStore }
import from 'expo-constants' { * as ExpoConstants }
import from 'react-error-boundary' { ErrorBoundary }
import from 'zod' { z }
import from client_runtime_core {
    __createJacSchema,
    jacIsLoggedIn,
    useJacForm,
    __jacReportError
}

def:pub __jacGetRenderer -> any;
def:pub __jacNativeCreate(
    tag: any, props: dict = {}, children: any = []
) -> JsxElement;

glob:pub useState = reactUseState,
     useEffect = reactUseEffect,
     Router = __nativeRouter,
     Routes = __nativeRoutes,
     Route = __nativeRoute,
     Link = __nativeLink,
     Navigate = __nativeNavigate,
     Outlet = __nativeOutlet,
     JacClientErrorBoundary = ErrorBoundary,
     JacSchema = __createJacSchema(z);

def:pub __nativeRouter(props: dict = {}) -> JsxElement;
def:pub __nativeRoutes(props: dict = {}) -> JsxElement;
def:pub __nativeRoute(props: dict = {}) -> JsxElement;
def:pub __nativeLink(props: dict = {}) -> JsxElement;
def:pub __nativeNavigate(props: dict = {}) -> JsxElement;
def:pub __nativeOutlet(props: dict = {}) -> JsxElement;
def:pub useRouter -> dict;
def:pub useNavigate -> any;
def:pub useLocation -> dict;
def:pub useParams -> dict;
def:pub navigate(path: str) -> None;
def:pub __getApiBaseUrl -> str;
def:pub __getLocalStorage(key: str) -> str;
def:pub __setLocalStorage(key: str, value: str) -> None;
def:pub __removeLocalStorage(key: str) -> None;
async def:pub __getLocalStorageAsync(key: str) -> str;
async def:pub __setLocalStorageAsync(key: str, value: str) -> None;
async def:pub __removeLocalStorageAsync(key: str) -> None;
async def:pub __primeNativeTokenCache -> None;
def:pub AuthGuard(redirect: str = "/login") -> JsxElement;
def:pub ErrorFallback(error: str, resetErrorBoundary: any) -> JsxElement;
def:pub JacAwaiting(props: dict) -> JsxElement;
def:pub errorOverlay(filePath: str, errors: str) -> JsxElement;
def:pub JacForm(props: dict) -> JsxElement;
def:pub __jacInstallErrorHandlers -> None;
def:pub __jacWirePlatformAdapters -> None;
