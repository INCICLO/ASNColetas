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

## Configuração

Execute `supabase/migrations/001_initial_schema.sql` no Supabase. No Netlify, configure `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY` e `SITE_URL`.

## Identidade visual

O projeto segue o Manual da Marca Inciclo: paleta oficial, tipografia Qanelas como referência, degradê e padrão institucional, respiro das marcas e uso das logos sem alteração de proporção, cor, fonte, sombra ou contorno.
