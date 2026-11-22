import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';

const BASE = __ENV.BASE_URL;
const RATE = parseInt(__ENV.RATE || '1000');

// [user_id, device_id] from the shared dataset
const users = new SharedArray('users', () =>
  open('/data/user.csv').trim().split('\n').slice(1).map((l) => {
    const c = l.split(',');
    return [c[0], c[1]];
  }));
const movies = new SharedArray('movies', () =>
  open('/data/movie.csv').trim().split('\n').slice(1, 1001).map((l) => l.split(',')[0]));

export const options = {
  scenarios: {
    load: {
      executor: 'constant-arrival-rate',   // keep a fixed number of requests per second
      rate: RATE,
      timeUnit: '1s',
      duration: __ENV.DURATION || '30s',
      preAllocatedVUs: 200,
      maxVUs: 1000,
    },
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const u = users[Math.floor(Math.random() * users.length)];
  const r = Math.random();
  let res;
  if (r < 0.7) {
    res = http.get(`${BASE}/rec/user/${u[0]}`, { tags: { name: 'read_by_user' } });
  } else if (r < 0.9) {
    res = http.get(`${BASE}/rec/device/${u[1]}`, { tags: { name: 'read_by_device' } });
  } else {
    const body = JSON.stringify({
      user_id: u[0],
      device_id: u[1],
      movie_id: movies[Math.floor(Math.random() * movies.length)],
      reaction_type: 'click',
    });
    res = http.post(`${BASE}/reaction`, body,
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'write_reaction' } });
  }
  check(res, { 'status is 200': (x) => x.status === 200 });
}
