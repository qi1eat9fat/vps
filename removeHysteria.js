function removeHysteria(proxies) {
  return proxies.filter(proxy => {
    // 检查 proxy.type 字段 或 名称中是否包含 hysteria
    if (!proxy.type && !proxy.name) return true; // 保留无关项

    const type = (proxy.type || '').toLowerCase();
    const name = (proxy.name || '').toLowerCase();

    // 只保留不是 hysteria 的节点
    return !(type.includes('hysteria') || name.includes('hysteria'));
  });
}
