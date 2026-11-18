import cors from 'cors'
import express from 'express'
import helmet from 'helmet'
import { config } from './config.js'
import { errorHandler, notFound } from './middleware/errors.js'
import { api } from './routes/index.js'

const app = express()
app.disable('x-powered-by')
app.set('trust proxy', 1) // behind App Runner / load balancer
app.use(helmet())
app.use(cors({ origin: config.corsOrigins }))
app.use(express.json({ limit: '50kb' }))

app.get('/health', (_req, res) => res.json({ status: 'ok' })) // root health check for load balancers
app.use('/api', api)
app.use(notFound)
app.use(errorHandler)

app.listen(config.port, () => {
  console.log(`StepUp API listening on :${config.port} (${config.isProd ? 'production' : 'development'}, demo data)`)
})
