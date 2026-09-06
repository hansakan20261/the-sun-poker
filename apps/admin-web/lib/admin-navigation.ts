export type BackofficeRole = "super_admin" | "admin" | "club_owner" | "club_admin" | "agent";

export type AdminMenuItem = {
  id: string;
  href: string;
  label: string;
  icon: string;
  roles: BackofficeRole[];
};

const platformRoles: BackofficeRole[] = ["super_admin", "admin"];
const clubRoles: BackofficeRole[] = ["club_owner", "club_admin"];

export const ADMIN_NAVIGATION: AdminMenuItem[] = [
  { id: "dashboard", href: "/dashboard", label: "Dashboard", icon: "D", roles: platformRoles },
  { id: "users", href: "/users", label: "ผู้ใช้งาน", icon: "U", roles: platformRoles },
  { id: "finance", href: "/coins", label: "เติม/ถอนเหรียญ", icon: "F", roles: platformRoles },
  { id: "clubs", href: "/clubs", label: "คลับ", icon: "C", roles: platformRoles },
  { id: "games", href: "/games", label: "เกมและห้องเล่น", icon: "G", roles: platformRoles },
  { id: "games-live", href: "/games/live", label: "Live Monitor", icon: "L", roles: platformRoles },
  { id: "tournaments", href: "/tournaments", label: "ทัวร์นาเมนต์", icon: "T", roles: platformRoles },
  { id: "agents", href: "/agents", label: "Agent", icon: "A", roles: platformRoles },
  { id: "agent-commission", href: "/agent-commission", label: "Commission", icon: "M", roles: platformRoles },
  { id: "rake-revenue", href: "/rake-revenue", label: "รายได้ Rake", icon: "R", roles: platformRoles },
  { id: "shop", href: "/shop", label: "ร้านค้า", icon: "S", roles: platformRoles },
  { id: "reports", href: "/reports", label: "รายงาน", icon: "P", roles: platformRoles },
  { id: "settings", href: "/settings", label: "ตั้งค่าระบบ", icon: "X", roles: platformRoles },
  { id: "menu-permissions", href: "/menu-permissions", label: "บทบาทและสิทธิ์", icon: "K", roles: platformRoles },
  { id: "agent-dashboard", href: "/agent-dashboard", label: "Agent Dashboard", icon: "D", roles: ["agent"] },
  { id: "agent-players", href: "/agent-players", label: "ลูกค้าของฉัน", icon: "U", roles: ["agent"] },
  { id: "agent-wallet", href: "/agent-wallet", label: "Agent Wallet", icon: "W", roles: ["agent"] },
  { id: "club-dashboard", href: "/club-dashboard", label: "Club Dashboard", icon: "D", roles: clubRoles },
  { id: "club-players", href: "/club-players", label: "ผู้เล่นในคลับ", icon: "U", roles: clubRoles },
  { id: "club-tables", href: "/club-tables", label: "โต๊ะในคลับ", icon: "G", roles: clubRoles },
];

export function defaultRouteForRole(role: string) {
  if (role === "agent") return "/agent-dashboard";
  if (role === "club_owner" || role === "club_admin") return "/club-dashboard";
  return "/dashboard";
}

export function menuForPath(pathname: string) {
  return [...ADMIN_NAVIGATION]
    .sort((a, b) => b.href.length - a.href.length)
    .find((item) => pathname === item.href || pathname.startsWith(`${item.href}/`));
}
