"use client";
import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { ADMIN_NAVIGATION } from "@/lib/admin-navigation";

const menuOptions = Array.from(new Map(ADMIN_NAVIGATION.map((item) => [item.id, item])).values());

export default function MenuPermissionsPage() {
  const [templates, setTemplates] = useState<any[]>([]);
  const [role, setRole] = useState("admin");
  const [menus, setMenus] = useState<string[]>([]);
  const [scope, setScope] = useState("all");
  const [userId, setUserId] = useState("");
  const [message, setMessage] = useState("");
  const selected = useMemo(() => templates.find((item) => item.role === role), [templates, role]);

  const load = () => api("/api/permissions-menu/templates").then((data) => setTemplates(data.templates || []));
  useEffect(() => { load(); }, []);
  useEffect(() => {
    setMenus(Array.isArray(selected?.menus) ? selected.menus : []);
    setScope(selected?.data_scope || "all");
  }, [selected]);

  const toggle = (id: string) => setMenus((current) => current.includes(id) ? current.filter((item) => item !== id) : [...current.filter((item) => item !== "all"), id]);
  const saveTemplate = async () => {
    await api(`/api/permissions-menu/templates/${role}`, {
      method: "PUT",
      body: JSON.stringify({ menus, data_scope: scope }),
    });
    setMessage("บันทึก Role Template แล้ว");
    load();
  };
  const loadUser = async () => {
    const data = await api(`/api/permissions-menu/users/${userId}`);
    setMenus(data.permissions.menus || []);
    setScope(data.permissions.data_scope || "all");
    setMessage(`โหลดสิทธิ์ของ ${data.user.username}`);
  };
  const saveUser = async () => {
    await api(`/api/permissions-menu/users/${userId}`, {
      method: "PUT",
      body: JSON.stringify({ menus, data_scope: scope, club_scope: null }),
    });
    setMessage("บันทึกสิทธิ์รายบุคคลแล้ว");
  };

  return <div>
    <h1 className="text-2xl font-bold text-sun-gold-light mb-6">บทบาทและสิทธิ์เมนู</h1>
    {message && <div className="card text-green-300 mb-4">{message}</div>}
    <div className="card mb-4 flex flex-wrap gap-3">
      <select className="input-field" value={role} onChange={(e) => setRole(e.target.value)}>
        {templates.map((item) => <option key={item.role} value={item.role}>{item.role}</option>)}
      </select>
      <select className="input-field" value={scope} onChange={(e) => setScope(e.target.value)}>
        <option value="all">All data</option><option value="own_club">Own club</option><option value="read_only">Read only</option>
      </select>
      <button className="btn-primary px-4" onClick={saveTemplate}>บันทึก Template</button>
    </div>
    <div className="card mb-4">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        {menuOptions.map((item) => <label key={item.id} className="flex gap-2 items-center"><input type="checkbox" checked={menus.includes("all") || menus.includes(item.id)} disabled={menus.includes("all")} onChange={() => toggle(item.id)} /><span>{item.label}</span></label>)}
      </div>
      <label className="flex gap-2 items-center mt-4"><input type="checkbox" checked={menus.includes("all")} onChange={(e) => setMenus(e.target.checked ? ["all"] : [])} /><span>ทุกเมนู</span></label>
    </div>
    <div className="card flex flex-wrap gap-3">
      <input className="input-field flex-1" placeholder="User UUID" value={userId} onChange={(e) => setUserId(e.target.value)} />
      <button className="btn-black px-4" onClick={loadUser} disabled={!userId}>โหลดสิทธิ์ User</button>
      <button className="btn-primary px-4" onClick={saveUser} disabled={!userId}>บันทึก User Override</button>
    </div>
  </div>;
}
