# Base Node Image
FROM node:18-alpine AS base
WORKDIR /app

RUN apk add --no-cache wget ca-certificates

FROM base AS supabase_install
RUN wget https://github.com/supabase/cli/releases/download/v1.152.4/supabase_1.152.4_linux_amd64.apk -O /tmp/supabase.apk \
    && apk add --allow-untrusted /tmp/supabase.apk

FROM supabase_install AS npm-install
COPY package*.json ./


USER root
RUN npm ci

FROM npm-install AS prebuild
# ----- Copy Code ------
RUN chown -R node:node /app
USER node
COPY --chown=node:node . .


# ---- Build -------
FROM prebuild AS build
RUN npm run build

#----- Supabase-init -----
FROM build AS supabase-init
RUN npx supabase start
RUN npx supabase status > supabase_status.txt

# ----- Extraction -----
FROM supabase-init AS supabase-status

# -----_Env alterations ------
FROM supabase-status AS env-setup
RUN SUPABASE_API_URL=$(grep -oP 'API URL: \K(.*)' supabase_status.txt) \
    && sed -i "s|NEXT_PUBLIC_SUPABASE_URL=.*|NEXT_PUBLIC_SUPABASE_URL=$SUPABASE_API_URL|" .env.local
RUN SUPABASE_ANON_KEY=$(grep -oP 'anon key: \K(.*)' supabase_status.txt) \
    && sed -i "s|NEXT_PUBLIC_SUPABASE_ANON_KEY=.*|NEXT_PUBLIC_SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY|" .env.local
RUN SUPABASE_SERVICE_ROLE_KEY=$(grep -oP 'service_role key: \K(.*)' supabase_status.txt) \
    && sed -i "s|SUPABASE_SERVICE_ROLE_KEY=.*|SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY|" .env.local
RUN export $(grep -v '^#' .env.local | xargs)


# Update SQL setup file
FROM env-setup AS sql-setup
RUN sed -i 's/project_url = "http:\/\/supabase_kong_chatbotui:8000"/project_url = "http:\/\/localhost:54321"/' supabase/migrations/20240108234540_setup.sql
RUN sed -i 's/service_role_key = "your-service-role-key"/service_role_key = "'$SUPABASE_SERVICE_ROLE_KEY'"/' supabase/migrations/20240108234540_setup.sql

# ----- db push ------
FROM sql-setup AS db-push
RUN npx supabase db push

# ---- Final Step -----
FROM db-push AS final
EXPOSE 3000
CMD ["npm", "run", "chat"]

#TODO: - section off dockerfile for image sizes
# - get .env values
# - run supabase status and fill in nextpublicsupabaseurl to .env.local
