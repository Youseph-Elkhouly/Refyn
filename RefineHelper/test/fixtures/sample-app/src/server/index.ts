import express from 'express';
import { listUsers } from '../services/users';

const app = express();
app.get('/api/users/:id', async (_req, res) => res.json(await listUsers()));
app.listen(3000);
