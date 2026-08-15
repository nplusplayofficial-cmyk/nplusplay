'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { signInWithEmail } from '@/lib/firebase/auth';
import { useAuth } from '@/lib/firebase/AuthContext';

export default function LoginPage() {
  const router = useRouter();
  const { user } = useAuth();

  const [activeTab, setActiveTab] = useState<'phone' | 'email'>('email');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [rememberMe, setRememberMe] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  // If already logged in, redirect to home
  if (user) {
    router.push('/');
    return null;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      // For simplicity, we always use email for login (Firebase supports email)
      const loginEmail = activeTab === 'phone' ? phone + '@phone.login' : email;
      await signInWithEmail(email, password);
      router.push('/');
    } catch (err: any) {
      setError(err.message || 'Login failed. Please check your credentials.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#0a0808] flex items-center justify-center p-4">
      <div className="w-full max-w-md">

        {/* Brand Header */}
        <div className="text-center mb-6">
          <h1 className="text-4xl font-black gold-text tracking-wider">N+ PLAY</h1>
        </div>

        {/* Login Card */}
        <div className="bg-[#0f172a] border border-[#2a2a3a] rounded-2xl p-6 shadow-2xl">
          <h2 className="text-2xl font-bold text-white mb-1">Login</h2>
          <p className="text-sm text-gray-400 mb-5">
            Please log in with your phone number or email
            <br />
            <span className="text-xs text-gray-500">If you forget your password, please contact customer service</span>
          </p>

          {/* Tabs: Phone / Email */}
          <div className="flex bg-[#1a1a2e] p-1 rounded-xl mb-5">
            <button
              onClick={() => setActiveTab('phone')}
              className={`flex-1 py-2 text-sm font-bold rounded-lg transition ${
                activeTab === 'phone'
                  ? 'bg-[#f5c518] text-black'
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              Phone Number
            </button>
            <button
              onClick={() => setActiveTab('email')}
              className={`flex-1 py-2 text-sm font-bold rounded-lg transition ${
                activeTab === 'email'
                  ? 'bg-[#f5c518] text-black'
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              Email
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Phone / Email Input */}
            {activeTab === 'phone' ? (
              <div>
                <label className="block text-xs font-medium text-gray-400 mb-1">Phone number</label>
                <div className="flex bg-[#1e293b] rounded-lg overflow-hidden border border-[#2a2a3a] focus-within:border-[#f5c518] transition">
                  <span className="flex items-center px-3 text-gray-400 text-sm border-r border-[#2a2a3a]">+91</span>
                  <input
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="Please enter the phone number"
                    className="w-full bg-transparent text-white px-4 py-3 text-sm outline-none"
                  />
                </div>
              </div>
            ) : (
              <div>
                <label className="block text-xs font-medium text-gray-400 mb-1">Email</label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="please input your email"
                  className="w-full bg-[#1e293b] border border-[#2a2a3a] focus:border-[#f5c518] text-white rounded-lg px-4 py-3 text-sm outline-none transition"
                  required
                />
              </div>
            )}

            {/* Password */}
            <div>
              <label className="block text-xs font-medium text-gray-400 mb-1">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Password"
                className="w-full bg-[#1e293b] border border-[#2a2a3a] focus:border-[#f5c518] text-white rounded-lg px-4 py-3 text-sm outline-none transition"
                required
              />
            </div>

            {/* Remember & Forgot Password */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={rememberMe}
                  onChange={(e) => setRememberMe(e.target.checked)}
                  className="w-4 h-4 accent-[#f5c518] bg-[#1e293b] border-[#2a2a3a] rounded"
                />
                <label className="text-xs text-gray-400">Remember password</label>
              </div>
              <button type="button" className="text-xs text-[#f5c518] hover:underline">
                Forgot password?
              </button>
            </div>

            {/* Error Message */}
            {error && <p className="text-red-500 text-xs font-medium">{error}</p>}

            {/* Login Button */}
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 bg-[#f5c518] hover:bg-[#e6b800] text-black font-bold rounded-lg transition disabled:opacity-50"
            >
              {loading ? 'Logging in...' : 'Log in'}
            </button>

            {/* Register Link */}
            <p className="text-center text-sm text-gray-400 mt-2">
              <Link href="/register" className="text-[#f5c518] font-bold hover:underline">Register</Link>
            </p>
          </form>
        </div>

        {/* Footer (Daman style weather/language) */}
        <div className="flex justify-between items-center text-xs text-gray-500 mt-4 px-2">
          <div className="flex items-center gap-2">
            <span>36°C</span>
            <span className="text-gray-600">|</span>
            <span>Mostly cloudy</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="font-bold text-gray-400">ENG</span>
            <span className="text-gray-600">|</span>
            <span>IN</span>
            <span className="text-gray-600">|</span>
            <span className="text-gray-400">{new Date().toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' }).replace(/\//g, '-')}</span>
          </div>
        </div>

      </div>
    </div>
  );
}
