"use client";
import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import { getToken, clearToken, authApi, permissionsApi } from "@/lib/api";
import { ADMIN_NAVIGATION, menuForPath } from "@/lib/admin-navigation";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<any>(null);
  const [permissions, setPermissions] = useState<any>(null);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);

  // Detect mobile screen
  useEffect(() => {
    const checkMobile = () => {
      const mobile = window.innerWidth < 768;
      setIsMobile(mobile);
      if (!mobile) setSidebarOpen(true); // Desktop: sidebar always open
    };
    checkMobile();
    window.addEventListener("resize", checkMobile);
    return () => window.removeEventListener("resize", checkMobile);
  }, []);

  useEffect(() => {
    const token = getToken();
    if (!token) { router.push("/login"); return; }
    Promise.all([authApi.me(), permissionsApi.me()]).then(([auth, access]) => {
      if (!["admin", "super_admin", "club_owner", "club_admin", "agent"].includes(auth.user.role)) {
        clearToken(); router.push("/login");
        return;
      }
      setUser(auth.user);
      setPermissions(access);
    }).catch(() => { clearToken(); router.push("/login"); });
  }, [router]);

  // Close sidebar on mobile when navigating
  useEffect(() => {
    if (isMobile) setSidebarOpen(false);
  }, [pathname, isMobile]);

  if (!user || !permissions) return (
    <div className="min-h-screen flex items-center justify-center">
      <p className="text-sun-gold text-xl">Loading...</p>
    </div>
  );

  const allowedMenus: string[] = Array.isArray(permissions.menus) ? permissions.menus : [];
  const menuItems = ADMIN_NAVIGATION.filter((item) =>
    item.roles.includes(user.role) && (allowedMenus.includes("all") || allowedMenus.includes(item.id))
  );
  const currentMenu = menuForPath(pathname);
  const authorized = currentMenu
    && currentMenu.roles.includes(user.role)
    && (allowedMenus.includes("all") || allowedMenus.includes(currentMenu.id));

  return (
    <div className="min-h-screen flex relative">
      {/* Mobile overlay */}
      {isMobile && sidebarOpen && (
        <div
          className="fixed inset-0 bg-black/60 z-40"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        ${isMobile ? "fixed inset-y-0 left-0 z-50" : "relative"}
        ${sidebarOpen ? "w-64 translate-x-0" : isMobile ? "-translate-x-full w-64" : "w-16"}
        bg-sun-black/95 border-r border-sun-gold/20 transition-all duration-300 flex flex-col
        ${isMobile ? "shadow-2xl" : ""}
      `}>
        <div className="p-4 border-b border-sun-gold/20 text-center">
          <img src="/logo.png" alt="THE SUN POKER" className={`mx-auto ${sidebarOpen ? "w-16 h-16" : "w-8 h-8"} transition-all`} />
          {sidebarOpen && <p className="text-sun-gold-light font-bold text-sm mt-2">THE SUN POKER</p>}
          {sidebarOpen && <p className="text-sun-gold/60 text-xs">Admin Panel</p>}
        </div>
        <nav className="flex-1 py-4 overflow-y-auto">
          {menuItems.map((item) => (
            <a key={item.href} href={item.href}
              className={`flex items-center px-4 py-3 text-sm transition-colors ${
                pathname === item.href
                  ? "bg-sun-red text-sun-gold-light border-r-2 border-sun-gold-light"
                  : "text-sun-gold/70 hover:bg-sun-red-dark hover:text-sun-gold-light"
              }`}>
              <span className="text-lg">{item.icon}</span>
              {sidebarOpen && <span className="ml-3">{item.label}</span>}
            </a>
          ))}
        </nav>
        <div className="p-4 border-t border-sun-gold/20">
          {sidebarOpen && (
            <div className="text-xs text-sun-gold/50 mb-2">
              👤 {user.display_name || user.username}
            </div>
          )}
          <button onClick={async () => {
            try { await authApi.logout(); } catch {}
            clearToken(); router.push("/login");
          }}
            className="text-red-400 hover:text-red-300 text-sm w-full text-left">
            {sidebarOpen ? "🚪 ออกจากระบบ" : "🚪"}
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0">
        <header className="bg-sun-black/50 border-b border-sun-gold/20 px-4 md:px-6 py-3 md:py-4 flex items-center justify-between sticky top-0 z-30">
          <button onClick={() => setSidebarOpen(!sidebarOpen)} className="text-sun-gold hover:text-sun-gold-light text-xl p-1">
            {sidebarOpen && !isMobile ? "◀" : "☰"}
          </button>
          <div className="text-sun-gold/60 text-xs md:text-sm truncate ml-2">
            THE SUN POKER Backoffice — {user.role.replaceAll("_", " ")}
          </div>
        </header>
        <div className="flex-1 p-3 md:p-6 overflow-auto">
          {authorized ? children : (
            <div className="card text-center text-red-300">ไม่มีสิทธิ์เข้าถึงเมนูนี้</div>
          )}
        </div>
      </main>
    </div>
  );
}
