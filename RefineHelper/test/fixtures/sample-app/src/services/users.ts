import { db } from '../db/client';

export async function listUsers() {
  return db.query('select * from users');
}
