# Recicle+ Trairi — Sistema Autônomo de Coletas

Aplicação web responsiva da Associação Sol Nascente para solicitação, análise, roteirização e execução de coletas seletivas no município de Trairi-CE.

## Arquitetura

- **GitHub:** código-fonte e histórico de versões.
- **Supabase:** PostgreSQL, autenticação, políticas de segurança e histórico operacional.
- **Netlify:** hospedagem, deploy contínuo e funções de envio de e-mail.
- **OpenStreetMap + Leaflet:** pesquisa, seleção e confirmação da localização.
- **Google Maps / Waze:** navegação do motorista.

## Funcionalidades

- Formulário público em cinco etapas com resumo antes do envio.
- Máscaras brasileiras para telefone, CNPJ e CEP.
- Endereço por pesquisa, clique no mapa ou GPS do aparelho.
- Protocolo `SOL-AAAA-XXXXXX` e acompanhamento público seguro.
- Recuperação de códigos por e-mail.
- Painel do gestor com indicadores, análise e histórico.
- Alocação automática: Centro para o triciclo; demais localidades para o Accelo 817.
- Rotas de até 10 pontos com vizinho mais próximo e melhoria 2-opt.
- Estimativa de distância e combustível por veículo.
- Interface móvel do motorista, navegação e registro de coleta/não coleta.

## 1. Supabase

1. Crie um projeto no Supabase.
2. Abra **SQL Editor → New query**.
3. Cole e execute `supabase/migrations/001_initial_schema.sql`.
4. Em **Authentication**, crie os usuários da equipe.
5. Para cada usuário, insira o perfil em `profiles` com um dos papéis: `manager`, `driver_truck` ou `driver_tricycle`.

Exemplo:

```sql
insert into public.profiles (id, full_name, role)
values ('UUID_DO_USUARIO', 'Nome do gestor', 'manager');
```

## 2. Netlify

Conecte este repositório ao Netlify. A configuração de build já está em `netlify.toml`.

Cadastre em **Site configuration → Environment variables**:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (somente nas funções; nunca use no front-end)
- `RESEND_API_KEY`
- `SITE_URL`

No serviço de e-mail, valide o domínio remetente usado em `netlify/functions/notify-request.ts`.

## Desenvolvimento local

```bash
cp .env.example .env
npm install
npm run dev
```

## Identidade visual

O projeto segue o Manual da Marca Inciclo: paleta oficial, tipografia Qanelas como referência, degradê e padrão institucional, respiro das marcas e uso das logos sem alteração de proporção, cor, fonte, sombra ou contorno.
