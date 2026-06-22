import { useState } from 'react';
import type { FormEvent } from 'react';

export function LoginView({ onLogin, isLoading, error }: { onLogin: (email: string, password: string) => Promise<void>; isLoading: boolean; error: string | null }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  async function submit(event: FormEvent) {
    event.preventDefault();
    await onLogin(email, password);
  }

  return (
    <main className="login-screen">
      <section className="login-panel">
        <div className="login-brand">
          <span>CareBridge</span>
          <h1>Admin Console</h1>
        </div>
        <form onSubmit={submit} className="login-form">
          <label>
            <span>Email</span>
            <input type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} required />
          </label>
          <label>
            <span>Password</span>
            <input type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required />
          </label>
          {error && <div className="form-error">{error}</div>}
          <button className="button button--primary" disabled={isLoading}>{isLoading ? 'Signing in...' : 'Sign in'}</button>
        </form>
      </section>
    </main>
  );
}