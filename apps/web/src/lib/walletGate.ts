type LoginFn = () => void | Promise<unknown>;

let loginFn: LoginFn | null = null;

export function registerWalletLogin(fn: LoginFn | null): void {
  loginFn = fn;
}

export function requestWalletLogin(): void {
  void loginFn?.();
}
