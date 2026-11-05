export function UserList() {
  const load = () => fetch('/api/users/42');
  return <button onClick={load}>Load</button>;
}
