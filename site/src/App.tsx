import Nav from "./components/Nav";
import Hero from "./components/Hero";
import Juxtapose from "./components/Juxtapose";
import Timeline from "./components/Timeline";
import HowItWorks from "./components/HowItWorks";
import Privacy from "./components/Privacy";
import Gallery from "./components/Gallery";
import Install from "./components/Install";
import Footer from "./components/Footer";

export default function App() {
  return (
    <>
      <div className="page-bg" aria-hidden="true" />
      <a className="skip-link" href="#sculpt">
        Skip to content
      </a>
      <Nav />
      <main>
        <Hero />
        <Juxtapose />
        <Timeline />
        <HowItWorks />
        <Privacy />
        <Gallery />
        <Install />
      </main>
      <Footer />
    </>
  );
}
