import {
  Box,
  Button,
  Container,
  CssBaseline,
  Divider,
  Grid,
  Stack,
  Typography,
} from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";

import Reveal from "@/landing/components/Reveal";
import { FAQ, FOOTER_NOTE, HERO, PRINCIPLES } from "@/landing/content";
import { landingTheme } from "@/landing/landingTheme";

export default function LandingApp() {
  return (
    <ThemeProvider theme={landingTheme} defaultMode="system">
      <CssBaseline />

      <Container maxWidth="md" component="main" sx={{ py: { xs: 8, md: 14 } }}>
        <Reveal>
          <Stack spacing={3} sx={{ maxWidth: "40rem" }}>
            <Typography variant="h1" component="h1">{HERO.headline}</Typography>
            <Typography variant="body1" color="text.secondary" sx={{ fontSize: "1.125rem" }}>
              {HERO.subhead}
            </Typography>
            <Stack direction={{ xs: "column", sm: "row" }} spacing={2}>
              <Button variant="contained" size="large" href={HERO.primaryCta.href}>
                {HERO.primaryCta.label}
              </Button>
              <Button variant="outlined" size="large" href={HERO.secondaryCta.href}>
                {HERO.secondaryCta.label}
              </Button>
            </Stack>
          </Stack>
        </Reveal>

        <Divider sx={{ my: { xs: 8, md: 12 } }} />

        <Box component="section" id="principles">
          <Typography variant="h2" component="h2" sx={{ mb: 4 }}>
            What it decides for you
          </Typography>
          <Grid container spacing={4}>
            {PRINCIPLES.map((item, index) => (
              <Grid key={item.title} size={{ xs: 12, sm: 6 }}>
                <Reveal delay={index * 60}>
                  <Typography variant="h3" component="h3" sx={{ mb: 1 }}>
                    {item.title}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {item.body}
                  </Typography>
                </Reveal>
              </Grid>
            ))}
          </Grid>
        </Box>

        <Divider sx={{ my: { xs: 8, md: 12 } }} />

        <Box component="section">
          <Typography variant="h2" component="h2" sx={{ mb: 4 }}>
            Questions
          </Typography>
          <Stack spacing={4}>
            {FAQ.map((item, index) => (
              <Reveal key={item.question} delay={index * 60}>
                <Typography variant="h3" component="h3" sx={{ mb: 1 }}>
                  {item.question}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {item.answer}
                </Typography>
              </Reveal>
            ))}
          </Stack>
        </Box>

        <Divider sx={{ my: { xs: 6, md: 10 } }} />

        <Typography variant="body2" color="text.secondary" component="footer">
          {FOOTER_NOTE}
        </Typography>
      </Container>
    </ThemeProvider>
  );
}
