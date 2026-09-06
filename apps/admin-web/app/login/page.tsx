"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { authApi, setToken } from "@/lib/api";
import { defaultRouteForRole } from "@/lib/admin-navigation";

export default function LoginPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(""); setLoading(true);
    try {
      const data = await authApi.login(username, password);
      if (!["admin", "super_admin", "club_owner", "club_admin", "agent"].includes(data.user.role)) {
        setError("ไม่มีสิทธิ์เข้าถึง Backoffice");
        return;
      }
      setToken(data.token);
      router.push(defaultRouteForRole(data.user.role));
    } catch (err: any) {
      setError(err.error || "เข้าสู่ระบบไม่สำเร็จ");
    } finally { setLoading(false); }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-b from-sun-red-dark to-sun-black">
      <form onSubmit={handleLogin} className="card w-full max-w-md">
        <div className="text-center mb-8">
          <img src="/logo.png" alt="THE SUN POKER" className="w-32 h-32 mx-auto" />
          <h2 className="text-2xl font-bold text-sun-gold-light mt-4">THE SUN POKER</h2>
          <p className="text-sun-gold/60 mt-1">Admin Panel</p>
        </div>
        {error && <div className="bg-red-900/50 border border-red-500 text-red-300 px-4 py-2 rounded mb-4 text-sm">{error}</div>}
        <input type="text" placeholder="Username" value={username} onChange={(e) => setUsername(e.target.value)}
          className="input-field mb-4" required />
        <input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)}
          className="input-field mb-6" required />
        <button type="submit" disabled={loading} className="btn-primary w-full">
          {loading ? "กำลังเข้าสู่ระบบ..." : "เข้าสู่ระบบ"}
        </button>
      </form>
    </div>
  );
}
